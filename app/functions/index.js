/**
 * Ikhlas Cloud Functions — Week 2: the deterministic gate engine.
 * Region pinned to asia-south1 (same as Firestore — required for the
 * v2 Firestore trigger and right for data residency).
 */
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const crypto = require('crypto');
const { evaluateGate } = require('./gate');
const { sendOtpEmail } = require('./resend');

// Resend transactional email. The API key is a secret:
//   firebase functions:secrets:set RESEND_API_KEY
// The sender must be an address on a domain verified in Resend
// (send.ikhlaas.io — SPF/DKIM/MX verified).
const RESEND_API_KEY = defineSecret('RESEND_API_KEY');
const RESEND_FROM = 'Ikhlaas <noreply@send.ikhlaas.io>';

initializeApp();
const db = getFirestore();
const REGION = 'asia-south1';

/**
 * Tier 1 — runs the moment an application is submitted.
 * Reads config/gateRules (tunable without an app release) + the user's
 * dob, decides auto_pass / auto_reject / manual_review, writes the
 * verdict onto the application doc (Admin SDK bypasses the client
 * immutability rules) and flips users.status — the only writer of
 * status in the system.
 */
exports.onApplicationSubmit = onDocumentCreated(
  { document: 'applications/{uid}', region: 'asia-south1' },
  async (event) => {
    const uid = event.params.uid;
    const application = event.data?.data();
    if (!application) return;

    // Already decided (duplicate event delivery) → no-op. Idempotency.
    if (application.decision || application.autoScore) return;

    const [rulesSnap, userSnap] = await Promise.all([
      db.doc('config/gateRules').get(),
      db.doc(`users/${uid}`).get(),
    ]);
    const rules = rulesSnap.exists ? rulesSnap.data() : {};
    const dobTs = userSnap.get('dob');
    const dob = dobTs ? dobTs.toDate() : null;

    const hasSelfie = Boolean(application.verification?.selfie?.storagePath);
    const verdict = evaluateGate(application.answers || {}, dob, rules, {
      hasSelfie,
    });

    const appUpdate = {
      autoScore: { result: verdict.result, reasons: verdict.reasons },
    };
    const userUpdate = { };

    switch (verdict.result) {
      case 'auto_pass':
        appUpdate.decision = 'approved';
        appUpdate.decidedAt = FieldValue.serverTimestamp();
        appUpdate.decidedBy = 'auto';
        userUpdate.status = 'approved';
        // E3(b) honest-disclosure badge — server-owned, top-level
        // (a protected field per firestore.rules; clients can't spoof it).
        if (application.answers?.e3_ribaPractice === 'exiting') {
          userUpdate.ribaDisclosureBadge = true;
        }
        break;
      case 'auto_reject':
        appUpdate.decision = 'soft_rejected';
        appUpdate.decidedAt = FieldValue.serverTimestamp();
        appUpdate.decidedBy = 'auto';
        userUpdate.status = 'soft_rejected';
        break;
      default: // manual_review — human queue (AI triage inserts here later)
        userUpdate.status = 'under_review';
        appUpdate.queue = 'human'; // admin dashboard queries on this
    }

    await Promise.all([
      db.doc(`applications/${uid}`).update(appUpdate),
      db.doc(`users/${uid}`).update(userUpdate),
    ]);

    console.log(
      `gate: uid=${uid} result=${verdict.result} reasons=${verdict.reasons.join('|')}`
    );
  }
);

/**
 * Decision notification — fires when the gate (auto) or a moderator
 * flips users.status. Copy follows the PRD tone and NEVER reveals AI
 * involvement ("reviewed by our team" stays true — a human is in the
 * loop on every non-obvious case).
 */
exports.notifyDecision = onDocumentUpdated(
  { document: 'users/{uid}', region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;

    const copy = {
      approved: {
        title: 'Welcome to Ikhlaas',
        body:
          'Alhamdulillah — your application has been accepted. ' +
          'Open the app to complete your profile.',
      },
      soft_rejected: {
        title: 'About your application',
        body:
          'JazakAllah khair for applying. Our team has reviewed your ' +
          'application — open the app to see the details.',
      },
    }[after.status];
    if (!copy) return;

    const tokens = Object.keys(after.fcmTokens || {});
    if (tokens.length === 0) return;

    const res = await getMessaging().sendEachForMulticast({
      tokens,
      notification: copy,
    });

    // Prune tokens that are permanently dead.
    const dead = {};
    res.responses.forEach((r, i) => {
      const code = r.error?.code || '';
      if (
        code.includes('registration-token-not-registered') ||
        code.includes('invalid-argument')
      ) {
        dead[`fcmTokens.${tokens[i]}`] = FieldValue.delete();
      }
    });
    if (Object.keys(dead).length > 0) {
      await db.doc(`users/${event.params.uid}`).update(dead);
    }
  }
);

/**
 * Account lifecycle — status is server-authoritative (rules law #2),
 * so pause/resume/delete are callables, never client writes.
 */
function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  return request.auth.uid;
}

exports.pauseAccount = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const snap = await db.doc(`users/${uid}`).get();
  if (snap.get('status') !== 'approved') {
    throw new HttpsError('failed-precondition', 'Only approved members pause.');
  }
  await db.doc(`users/${uid}`).update({ status: 'paused' });
  return { ok: true };
});

exports.resumeAccount = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const snap = await db.doc(`users/${uid}`).get();
  if (snap.get('status') !== 'paused') {
    throw new HttpsError('failed-precondition', 'Account is not paused.');
  }
  await db.doc(`users/${uid}`).update({ status: 'approved' });
  return { ok: true };
});

/**
 * DPDP self-serve deletion: auth user, user doc, application doc and
 * every stored file (photos + verification selfie). Best-effort on
 * storage so a missing file never strands the deletion.
 */
exports.deleteAccount = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  try {
    await getStorage().bucket().deleteFiles({ prefix: `users/${uid}/` });
  } catch (e) {
    console.warn(`storage cleanup for ${uid}: ${e.message}`);
  }
  await db.doc(`applications/${uid}`).delete();
  await db.doc(`users/${uid}`).delete();
  await getAuth().deleteUser(uid);
  console.log(`account deleted: ${uid}`);
  return { ok: true };
});

// ============================================================
// Phase 2 — Matching engine (PRD §4.2: curated daily batch, not swiping)
// ============================================================
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { buildBatch, istDateString } = require('./matching');

/** Loads the full snapshot pool: approved+complete users joined with
 *  their application answers (prayer/timeframe drive deen scoring). */
async function loadPool() {
  const [usersSnap, appsSnap] = await Promise.all([
    db.collection('users')
      .where('status', '==', 'approved')
      .where('profileComplete', '==', true)
      .get(),
    db.collection('applications').get(),
  ]);
  const answers = {};
  appsSnap.forEach((d) => (answers[d.id] = d.get('answers') || {}));
  const names = {};
  appsSnap.forEach(
    (d) => (names[d.id] = (d.get('intentDeclaration.typedName') || '').split(' ')[0])
  );
  return usersSnap.docs.map((d) => {
    const u = d.data();
    return {
      _id: d.id,
      status: u.status,
      profileComplete: u.profileComplete === true,
      gender: u.gender,
      dob: u.dob?.toDate?.() || null,
      lastActiveAt: u.lastActiveAt?.toDate?.() || null,
      profile: u.profile || {},
      preferences: u.preferences || {},
      answers: answers[d.id] || {},
      displayName: names[d.id] || 'Member',
      ribaBadge: u.ribaDisclosureBadge === true,
      hasPhotos: (u.photos || []).length > 0,
      photoPrivacy: u.photoPrivacy || 'blur_until_match',
      blockedUids: u.blockedUids || [],
      fcmTokens: u.fcmTokens || {},
    };
  });
}

function entrySnapshot(e) {
  const c = e.candidate;
  const now = new Date();
  let age = null;
  if (c.dob) {
    age = now.getFullYear() - c.dob.getFullYear();
    if (
      now.getMonth() < c.dob.getMonth() ||
      (now.getMonth() === c.dob.getMonth() && now.getDate() < c.dob.getDate())
    ) age--;
  }
  return {
    displayName: c.displayName,
    age,
    gender: c.gender,
    city: c.profile.city || null,
    country: c.profile.country || null,
    profession: c.profile.profession || null,
    education: c.profile.education || null,
    languages: c.profile.languages || [],
    maritalStatus: c.profile.maritalStatus || null,
    hasChildren: c.profile.hasChildren ?? null,
    revert: c.profile.revert === true,
    sect: c.profile.sect || null,
    madhhab: c.profile.madhhab || null,
    prayer: c.answers.prayer || null,
    timeframe: c.answers.timeframe || null,
    ribaDisclosureBadge: c.ribaBadge,
    hasPhotos: c.hasPhotos === true,
    photoPrivacy: c.photoPrivacy || 'blur_until_match',
    bioPrompts: c.profile.bioPrompts || [],
    // Section D answers are shown on the profile to matches (disclosed to
    // the applicant at entry) as well as used for review.
    whyNow: c.answers.shortAnswers?.whyNow || null,
    deenRelationship: c.answers.shortAnswers?.deenRelationship || null,
    compatibility: e.why,           // "You both pray five daily" etc.
    score: e.score,                  // internal; not rendered to users
    action: null,
    actionAt: null,
  };
}

/** Writes one user's batch: batch doc + entry docs + seen markers. */
async function writeBatchFor(user, pool, date) {
  const seenSnap = await db.collection(`matches/${user._id}/seen`).get();
  const seen = new Set(seenSnap.docs.map((d) => d.id));
  const interestsSnap = await db
    .collection('interests')
    .where('to', '==', user._id)
    .get();
  const interestedInMe = new Set(interestsSnap.docs.map((d) => d.get('from')));
  const blocked = new Set(user.blockedUids || []);

  const batch = buildBatch(user, pool, { seen, interestedInMe, blocked });
  if (batch.length === 0) return 0;

  const wb = db.batch();
  const batchRef = db.doc(`matches/${user._id}/batches/${date}`);
  wb.set(batchRef, {
    date,
    generatedAt: FieldValue.serverTimestamp(),
    count: batch.length,
  });
  for (const e of batch) {
    wb.set(batchRef.collection('entries').doc(e.candidate._id), entrySnapshot(e));
    wb.set(db.doc(`matches/${user._id}/seen/${e.candidate._id}`), {
      at: FieldValue.serverTimestamp(),
      batchDate: date,
    });
  }
  await wb.commit();

  const tokens = Object.keys(user.fcmTokens);
  if (tokens.length > 0) {
    await getMessaging()
      .sendEachForMulticast({
        tokens,
        notification: {
          title: 'Your matches have arrived',
          body: `${batch.length} carefully chosen ${
            batch.length === 1 ? 'profile' : 'profiles'
          } await you today, bi'idhnillah.`,
        },
      })
      .catch(() => {});
  }
  return batch.length;
}

/** Daily batch generation — after Fajr, 07:00 IST (PRD: on-brand hour). */
exports.generateDailyBatches = onSchedule(
  { schedule: '0 7 * * *', timeZone: 'Asia/Kolkata', region: REGION },
  async () => {
    const pool = await loadPool();
    const date = istDateString();
    let total = 0;
    for (const user of pool) {
      const existing = await db.doc(`matches/${user._id}/batches/${date}`).get();
      if (existing.exists) continue;
      total += await writeBatchFor(user, pool, date);
    }
    console.log(`daily batches for ${date}: ${total} entries across ${pool.length} members`);
  }
);

/** On-demand batch (new members mid-day + testing). Idempotent per day. */
exports.generateMyBatch = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const date = istDateString();
  const existing = await db.doc(`matches/${uid}/batches/${date}`).get();
  if (existing.exists) return { date, created: false };
  const pool = await loadPool();
  const me = pool.find((u) => u._id === uid);
  if (!me) {
    throw new HttpsError('failed-precondition', 'Approved, complete profiles only.');
  }
  const n = await writeBatchFor(me, pool, date);
  return { date, created: n > 0, count: n };
});

/** Interest/pass on a batch entry → interests ledger → mutual detection.
 *  Mutual interest opens a conversation (stage: intro) — the PRD's
 *  guarded-communication starting point. No "likes you" surface exists;
 *  interest is only ever revealed through mutuality. */
exports.onEntryAction = onDocumentUpdated(
  { document: 'matches/{uid}/batches/{date}/entries/{otherUid}', region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.action === after.action) return;
    const { uid, otherUid } = event.params;

    if (after.action !== 'interested') return;

    await db.doc(`interests/${uid}_${otherUid}`).set({
      from: uid,
      to: otherUid,
      at: FieldValue.serverTimestamp(),
    });

    const reciprocal = await db.doc(`interests/${otherUid}_${uid}`).get();
    if (!reciprocal.exists) return;

    // Mutual, alhamdulillah — open the guarded conversation.
    const convId = [uid, otherUid].sort().join('_');
    const convRef = db.doc(`conversations/${convId}`);
    if ((await convRef.get()).exists) return;

    // 3-active-conversation cap (PRD §4.4). If either party is already at
    // three, hold the match open until they close one — notify, don't drop.
    const [na, nb] = await Promise.all([
      activeConversationCount(uid),
      activeConversationCount(otherUid),
    ]);
    if (na >= 3 || nb >= 3) {
      const full = na >= 3 ? uid : otherUid;
      const tokens = Object.keys(
        (await db.doc(`users/${full}`).get()).get('fcmTokens') || {}
      );
      if (tokens.length > 0) {
        await getMessaging()
          .sendEachForMulticast({
            tokens,
            notification: {
              title: 'A new match is waiting',
              body:
                'You have a mutual match, but you are at three active ' +
                'conversations. Close one with dua to connect.',
            },
          })
          .catch(() => {});
      }
      return; // conversation opens once a slot frees (re-checked on next action)
    }

    // Wali visibility + denormalised profile snapshots so the chat can show
    // each match's name/profile (a member can't read the other's users doc).
    const [ua, ub, appA, appB] = await Promise.all([
      db.doc(`users/${uid}`).get(),
      db.doc(`users/${otherUid}`).get(),
      db.doc(`applications/${uid}`).get(),
      db.doc(`applications/${otherUid}`).get(),
    ]);
    const observing =
      ua.get('wali')?.permissionLevel === 'observe' ||
      ub.get('wali')?.permissionLevel === 'observe';

    await convRef.set({
      participants: [uid, otherUid].sort(),
      stage: 'intro',                       // → deepening → family → closed_*
      stageHistory: [
        { stage: 'intro', at: new Date() }, // auditable event log (PRD §8)
      ],
      adabAcknowledged: {},
      waliObserving: observing,
      profiles: {
        [uid]: chatProfile(ua, appA),
        [otherUid]: chatProfile(ub, appB),
      },
      photoReveal: {},
      photoRevealRequests: {},
      createdAt: FieldValue.serverTimestamp(),
      lastMessageAt: null,
    });

    const both = await Promise.all([
      db.doc(`users/${uid}`).get(),
      db.doc(`users/${otherUid}`).get(),
    ]);
    for (const snap of both) {
      const tokens = Object.keys(snap.get('fcmTokens') || {});
      if (tokens.length > 0) {
        await getMessaging()
          .sendEachForMulticast({
            tokens,
            notification: {
              title: 'A mutual match, alhamdulillah',
              body: 'You both expressed interest. A guarded conversation is now open.',
            },
          })
          .catch(() => {});
      }
    }
  }
);

// ============================================================
// Photo pipeline (PRD §4.3) — originals never exposed. Every render
// goes through this function: permission-checked, blurred per privacy
// mode, watermarked with the viewer's id for leak tracing.
// ============================================================
const { onRequest } = require('firebase-functions/v2/https');
const { processPhoto, decideVisibility } = require('./photos');

const convIdOf = (a, b) => [a, b].sort().join('_');

exports.photo = onRequest(
  { region: REGION, memory: '512MiB', cors: true },
  async (req, res) => {
    try {
      const authz = req.get('Authorization') || '';
      const m = authz.match(/^Bearer (.+)$/);
      if (!m) return res.status(401).send('unauthenticated');
      const viewer = (await getAuth().verifyIdToken(m[1])).uid;

      const owner = String(req.query.owner || '');
      const idx = parseInt(req.query.idx || '0', 10) || 0;
      if (!owner) return res.status(400).send('owner required');

      const ownerSnap = await db.doc(`users/${owner}`).get();
      if (!ownerSnap.exists) return res.status(404).send('not found');
      const photos = ownerSnap.get('photos') || [];
      if (idx >= photos.length) return res.status(404).send('no such photo');

      const convSnap =
        viewer === owner
          ? null
          : await db.doc(`conversations/${convIdOf(viewer, owner)}`).get();
      const matched = !!convSnap && convSnap.exists;
      const revealGranted =
        matched && (convSnap.get('photoReveal')?.[owner] === true);
      const today = new Date(Date.now() + 5.5 * 3600 * 1000)
        .toISOString()
        .slice(0, 10);
      const inBatch = viewer === owner
        ? false
        : (await db
            .doc(`matches/${viewer}/batches/${today}/entries/${owner}`)
            .get()).exists;

      // Owner always sees their own photos, unblurred, no watermark.
      let allowed = true;
      let blur = false;
      if (viewer !== owner) {
        const vis = decideVisibility({
          privacy: ownerSnap.get('photoPrivacy') || 'blur_until_match',
          matched,
          revealGranted,
          inViewerBatch: inBatch,
        });
        allowed = vis.allowed;
        blur = vis.blur;
      }
      if (!allowed) return res.status(403).send('not permitted');

      const [bytes] = await getStorage()
        .bucket()
        .file(photos[idx].storagePath)
        .download();
      const out = await processPhoto(bytes, {
        blur,
        watermarkText: viewer === owner ? null : viewer.slice(0, 8),
      });

      res.set('Cache-Control', 'private, max-age=300');
      res.set('Content-Type', 'image/jpeg');
      return res.status(200).send(out);
    } catch (e) {
      console.error('photo error', e);
      return res.status(500).send('error');
    }
  }
);

// ============================================================
// Guarded chat (PRD §4.4) — adab gate, contact-info blocking, 3-active
// cap, 14-day lifecycle, End-with-dua. All writes are server-mediated.
// ============================================================

// Blocks phone numbers, emails, and off-app move attempts pre-Family Stage.
const CONTACT_PATTERNS = [
  /\b(?:\+?\d[\s-]?){7,}\b/, // phone-like digit runs
  /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, // email
  /\b(whats\s?app|whatsapp|w\.?a\.?|insta(gram)?|telegram|t\.me|snap(chat)?|@[a-z0-9_.]{2,})\b/i,
  /\b(my\s+number|call\s+me|text\s+me|move\s+(to|off)|off[-\s]?app)\b/i,
];

function containsContactInfo(text) {
  return CONTACT_PATTERNS.some((re) => re.test(text));
}

async function activeConversationCount(uid) {
  const snap = await db
    .collection('conversations')
    .where('participants', 'array-contains', uid)
    .get();
  return snap.docs.filter((d) => !String(d.get('stage')).startsWith('closed_'))
    .length;
}

exports.acknowledgeAdab = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const convId = request.data?.convId;
  const ref = db.doc(`conversations/${convId}`);
  const snap = await ref.get();
  if (!snap.exists || !snap.get('participants').includes(uid)) {
    throw new HttpsError('permission-denied', 'Not your conversation.');
  }
  await ref.update({ [`adabAcknowledged.${uid}`]: true });
  return { ok: true };
});

exports.sendMessage = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const { convId, text } = request.data || {};
  const body = String(text || '').trim();
  if (!body) throw new HttpsError('invalid-argument', 'Empty message.');
  if (body.length > 2000) throw new HttpsError('invalid-argument', 'Too long.');

  const ref = db.doc(`conversations/${convId}`);
  const snap = await ref.get();
  if (!snap.exists || !snap.get('participants').includes(uid)) {
    throw new HttpsError('permission-denied', 'Not your conversation.');
  }
  if (String(snap.get('stage')).startsWith('closed_')) {
    throw new HttpsError('failed-precondition', 'This conversation is closed.');
  }
  // Blocks and warns (PRD §4.4) — the message is NOT delivered.
  if (containsContactInfo(body)) {
    throw new HttpsError(
      'invalid-argument',
      'Sharing contact details or moving off Ikhlaas is not allowed before ' +
        'the Family Stage. Please keep the conversation here.'
    );
  }
  await ref.collection('messages').add({
    from: uid,
    text: body,
    at: FieldValue.serverTimestamp(),
  });
  await ref.update({
    lastMessageAt: FieldValue.serverTimestamp(),
    [`nudged`]: FieldValue.delete(),
  });

  const other = snap.get('participants').find((p) => p !== uid);
  const tokens = Object.keys(
    (await db.doc(`users/${other}`).get()).get('fcmTokens') || {}
  );
  if (tokens.length > 0) {
    await getMessaging()
      .sendEachForMulticast({
        tokens,
        notification: { title: 'New message', body: 'You have a new message on Ikhlaas.' },
      })
      .catch(() => {});
  }
  return { ok: true };
});

exports.grantPhotoReveal = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const convId = request.data?.convId;
  const ref = db.doc(`conversations/${convId}`);
  const snap = await ref.get();
  if (!snap.exists || !snap.get('participants').includes(uid)) {
    throw new HttpsError('permission-denied', 'Not your conversation.');
  }
  // The owner grants reveal of THEIR photos to this conversation; revocable.
  const grant = request.data?.revoke ? false : true;
  await ref.update({ [`photoReveal.${uid}`]: grant });
  return { ok: true, granted: grant };
});

exports.endWithDua = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const convId = request.data?.convId;
  const ref = db.doc(`conversations/${convId}`);
  const snap = await ref.get();
  if (!snap.exists || !snap.get('participants').includes(uid)) {
    throw new HttpsError('permission-denied', 'Not your conversation.');
  }
  if (String(snap.get('stage')).startsWith('closed_')) return { ok: true };
  await ref.collection('messages').add({
    from: 'system',
    text:
      'JazakAllah khair for your time — I don’t feel we’re a match. ' +
      'May Allah grant you a righteous spouse.',
    at: FieldValue.serverTimestamp(),
    system: true,
  });
  await ref.update({
    stage: 'closed_dua',
    stageHistory: FieldValue.arrayUnion({ stage: 'closed_dua', at: new Date(), by: uid }),
    closedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/**
 * 14-day lifecycle (PRD §4.4): 7 days silent → nudge both; 14 days →
 * auto-archive with a respectful closure. Kills zombie chats.
 */
exports.archiveStaleConversations = onSchedule(
  { schedule: '0 8 * * *', timeZone: 'Asia/Kolkata', region: REGION },
  async () => {
    const now = Date.now();
    const snap = await db.collection('conversations').get();
    for (const d of snap.docs) {
      const stage = String(d.get('stage'));
      if (stage.startsWith('closed_')) continue;
      const last =
        d.get('lastMessageAt')?.toMillis?.() ||
        d.get('createdAt')?.toMillis?.() ||
        now;
      const days = (now - last) / (24 * 3600 * 1000);

      if (days >= 14) {
        await d.ref.collection('messages').add({
          from: 'system',
          text:
            'This conversation has rested for two weeks, so we have closed it ' +
            'gently. May Allah write what is best for you both.',
          at: FieldValue.serverTimestamp(),
          system: true,
        });
        await d.ref.update({
          stage: 'closed_timeout',
          stageHistory: FieldValue.arrayUnion({ stage: 'closed_timeout', at: new Date() }),
          closedAt: FieldValue.serverTimestamp(),
        });
      } else if (days >= 7 && !d.get('nudged')) {
        await d.ref.update({ nudged: true });
        for (const uid of d.get('participants')) {
          const tokens = Object.keys(
            (await db.doc(`users/${uid}`).get()).get('fcmTokens') || {}
          );
          if (tokens.length > 0) {
            await getMessaging()
              .sendEachForMulticast({
                tokens,
                notification: {
                  title: 'A conversation is waiting',
                  body:
                    'A match is still open — a kind word keeps it alive. ' +
                    'Conversations rest after 14 days of silence.',
                },
              })
              .catch(() => {});
          }
        }
      }
    }
  }
);

// ============================================================
// Phase 3 — Family Stage (PRD §4.4 Stage 3). The app's success event:
// "Family Stage initiations per 100 members" is the north star.
// ============================================================

async function convForMember(convId, uid) {
  const ref = db.doc(`conversations/${convId}`);
  const snap = await ref.get();
  if (!snap.exists || !snap.get('participants').includes(uid)) {
    throw new HttpsError('permission-denied', 'Not your conversation.');
  }
  if (String(snap.get('stage')).startsWith('closed_')) {
    throw new HttpsError('failed-precondition', 'This conversation is closed.');
  }
  return { ref, snap };
}

/** Either party taps "Involve families" → records the request, notifies. */
exports.requestFamilyStage = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const { ref, snap } = await convForMember(request.data?.convId, uid);
  if (snap.get('familyStage')?.confirmed) return { ok: true };
  await ref.update({
    'familyStage.requestedBy': uid,
    'familyStage.requestedAt': FieldValue.serverTimestamp(),
  });
  await ref.collection('messages').add({
    from: 'system',
    system: true,
    text: 'A request to involve families has been made. When both agree, '
      + 'guardian contacts are exchanged to take things forward, insha’Allah.',
    at: FieldValue.serverTimestamp(),
  });
  const other = snap.get('participants').find((p) => p !== uid);
  await pushTo(other, 'Involve families?',
    'Your match has asked to bring families into the conversation.');
  return { ok: true };
});

/** The other party confirms → stage=family, structured Wali exchange,
 *  meeting intent recorded. THE north-star event. */
exports.confirmFamilyStage = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const { ref, snap } = await convForMember(request.data?.convId, uid);
  const fs = snap.get('familyStage') || {};
  if (!fs.requestedBy || fs.requestedBy === uid) {
    throw new HttpsError('failed-precondition',
      'The other party must request the Family Stage first.');
  }

  const parts = snap.get('participants');
  const [ua, ub] = await Promise.all(parts.map((p) => db.doc(`users/${p}`).get()));
  const waliOf = (u) => {
    const w = u.get('wali');
    return w ? { name: w.name, relationship: w.relationship, phone: w.phone } : null;
  };
  // Wali contact details shared THROUGH the app (never typed in chat).
  const exchange = {
    [parts[0]]: waliOf(ua),
    [parts[1]]: waliOf(ub),
  };

  await ref.update({
    stage: 'family',
    'familyStage.confirmed': true,
    'familyStage.confirmedBy': uid,
    'familyStage.confirmedAt': FieldValue.serverTimestamp(),
    familyExchange: exchange,
    stageHistory: FieldValue.arrayUnion({ stage: 'family', at: new Date() }),
  });
  await ref.collection('messages').add({
    from: 'system',
    system: true,
    text: 'Family Stage reached, alhamdulillah. Guardian contacts have been '
      + 'shared with both sides. May Allah bless this path.',
    at: FieldValue.serverTimestamp(),
  });

  // North-star metric event — immutable analytics record.
  await db.collection('metrics_familyStage').add({
    convId: ref.id,
    participants: parts,
    at: FieldValue.serverTimestamp(),
  });

  // Notify both members and any observing Walis.
  for (const p of parts) {
    await pushTo(p, 'Family Stage reached',
      'Guardian contacts have been exchanged. May Allah make it easy.');
  }
  await notifyWalisOf(parts, 'Family Stage reached',
    'A conversation you oversee has reached the Family Stage.');
  return { ok: true };
});

// ============================================================
// Phase 3 — Trust, safety & moderation (PRD §4.6)
// ============================================================

const REPORT_REASONS = [
  'not_serious', 'already_married', 'inappropriate',
  'off_app', 'fake_profile', 'harassment',
];

exports.reportUser = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const { reportedUid, reason, detail, convId } = request.data || {};
  if (!reportedUid || !REPORT_REASONS.includes(reason)) {
    throw new HttpsError('invalid-argument', 'Invalid report.');
  }
  await db.collection('reports').add({
    reporterUid: uid,
    reportedUid,
    reason,
    detail: (detail || '').slice(0, 500),
    convId: convId || null,
    status: 'open',
    createdAt: FieldValue.serverTimestamp(),
  });

  // Report → auto-freeze the conversation for review (< 24h target).
  if (convId) {
    await db.doc(`conversations/${convId}`)
      .update({ frozen: true, frozenReason: 'reported' })
      .catch(() => {});
  }

  // "Not serious" reports are first-class: 2 independent ones → re-review.
  if (reason === 'not_serious') {
    const priors = await db.collection('reports')
      .where('reportedUid', '==', reportedUid)
      .where('reason', '==', 'not_serious')
      .get();
    const distinct = new Set(priors.docs.map((d) => d.get('reporterUid')));
    if (distinct.size >= 2) {
      await db.doc(`users/${reportedUid}`)
        .update({ seriousnessReview: true }).catch(() => {});
    }
  }
  return { ok: true };
});

/** Block → instant mutual invisibility forever (PRD §4.6). Closes any
 *  open conversation and removes each from the other's matching pool. */
exports.blockUser = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const other = request.data?.otherUid;
  if (!other) throw new HttpsError('invalid-argument', 'Missing user.');
  await Promise.all([
    db.doc(`users/${uid}`).set(
      { blockedUids: FieldValue.arrayUnion(other) }, { merge: true }),
    db.doc(`users/${other}`).set(
      { blockedUids: FieldValue.arrayUnion(uid) }, { merge: true }),
  ]);
  const convId = convIdOf(uid, other);
  await db.doc(`conversations/${convId}`).update({
    stage: 'closed_blocked',
    closedAt: FieldValue.serverTimestamp(),
    stageHistory: FieldValue.arrayUnion({ stage: 'closed_blocked', at: new Date() }),
  }).catch(() => {});
  return { ok: true };
});

/** Moderator resolves a report: dismiss, or apply a strike escalation. */
exports.moderateReport = onCall({ region: REGION }, async (request) => {
  const modUid = requireAuth(request);
  if (request.auth.token.moderator !== true) {
    throw new HttpsError('permission-denied', 'Moderators only.');
  }
  const { reportId, action, reportedUid } = request.data || {};
  // action: 'dismiss' | 'warn' | 'suspend' | 'ban'
  if (reportId) {
    await db.doc(`reports/${reportId}`).update({
      status: 'resolved',
      resolvedBy: modUid,
      action: action || 'dismiss',
      resolvedAt: FieldValue.serverTimestamp(),
    });
  }
  if (!reportedUid || action === 'dismiss' || !action) return { ok: true };

  const userRef = db.doc(`users/${reportedUid}`);
  const snap = await userRef.get();
  const strikes = (snap.get('strikes') || 0) + 1;

  if (action === 'warn') {
    await userRef.update({ strikes });
    await pushTo(reportedUid, 'A note from Ikhlaas',
      'A concern was raised about your conduct. Please uphold the adab of Ikhlaas.');
  } else if (action === 'suspend') {
    const until = Date.now() + 7 * 24 * 3600 * 1000;
    await userRef.update({
      strikes, status: 'suspended',
      suspendedUntil: new Date(until),
    });
    await pushTo(reportedUid, 'Account suspended',
      'Your account is suspended for 7 days following a review.');
  } else if (action === 'ban') {
    await userRef.update({ strikes: 3, status: 'banned' });
    const phone = snap.get('phone');
    if (phone) {
      await db.doc(`banRegistry/${phone.replace(/[^0-9]/g, '')}`)
        .set({ uid: reportedUid, at: FieldValue.serverTimestamp(), key: 'phone' });
    }
  }
  return { ok: true, strikes };
});

// ============================================================
// Phase 3 — Wali / Guardian portal (PRD §4.5). Magic-link + OTP; no app
// install, no password. SMS delivery is stubbed until DLT registration.
// ============================================================

function sixDigit(seed) {
  // Deterministic-free is fine here; derive from crypto.
  return String(require('crypto').randomInt(100000, 1000000));
}

/** Seeker invites their Wali. Creates an invite + OTP; (stub) sends SMS. */
exports.sendWaliInvite = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const userSnap = await db.doc(`users/${uid}`).get();
  const wali = userSnap.get('wali');
  if (!wali?.phone) {
    throw new HttpsError('failed-precondition', 'Add a Wali first.');
  }
  const code = sixDigit();
  const inviteRef = await db.collection('waliInvites').add({
    ward: uid,
    wardName: userSnap.get('profile.displayName') || 'your ward',
    phone: wali.phone,
    code,
    verified: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  // STUB: real SMS via MSG91 once DLT registration completes.
  console.log(`[wali-invite STUB] to ${wali.phone}: ` +
    `https://wali.ikhlaas.io/?invite=${inviteRef.id} code ${code}`);
  return { ok: true, inviteId: inviteRef.id };
});

/** Wali enters the OTP → we mint a Firebase custom token scoped to the
 *  ward, which the portal uses to sign in. No password, no app. */
exports.waliVerify = onCall({ region: REGION }, async (request) => {
  const { inviteId, code } = request.data || {};
  const ref = db.doc(`waliInvites/${inviteId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Invite not found.');
  if (String(snap.get('code')) !== String(code)) {
    throw new HttpsError('permission-denied', 'Incorrect code.');
  }
  const ward = snap.get('ward');
  await Promise.all([
    ref.update({ verified: true, verifiedAt: FieldValue.serverTimestamp() }),
    db.doc(`users/${ward}`).update({ 'wali.verified': true }).catch(() => {}),
  ]);
  const token = await getAuth().createCustomToken(`wali_${ward}`, {
    wali: true,
    ward,
  });
  return { token, ward };
});

/** Wali flags a concern to the ward (does not hard-block in v1). */
exports.waliRequestPause = onCall({ region: REGION }, async (request) => {
  if (request.auth?.token?.wali !== true) {
    throw new HttpsError('permission-denied', 'Wali only.');
  }
  const ward = request.auth.token.ward;
  await db.doc(`users/${ward}`).set(
    { waliConcernRaisedAt: FieldValue.serverTimestamp() }, { merge: true });
  await pushTo(ward, 'A note from your Wali',
    'Your Wali has raised a concern and asked to pause. Please speak with them.');
  return { ok: true };
});

// ---- shared notification helpers ----
async function pushTo(uid, title, body) {
  const tokens = Object.keys(
    (await db.doc(`users/${uid}`).get()).get('fcmTokens') || {}
  );
  if (tokens.length === 0) return;
  await getMessaging()
    .sendEachForMulticast({ tokens, notification: { title, body } })
    .catch(() => {});
}

async function notifyWalisOf(uids, title, body) {
  for (const uid of uids) {
    const w = (await db.doc(`users/${uid}`).get()).get('wali');
    if (w?.permissionLevel === 'observe' && w?.phone) {
      console.log(`[wali-notify STUB] ${w.phone}: ${title} — ${body}`);
    }
  }
}

/** Compact profile snapshot stored on a conversation so each participant
 *  can render the other's name/profile without reading their users doc. */
function chatProfile(userSnap, appSnap) {
  const u = userSnap.data() || {};
  const p = u.profile || {};
  const a = (appSnap.exists && appSnap.get('answers')) || {};
  let age = null;
  const dob = u.dob?.toDate ? u.dob.toDate() : null;
  if (dob) {
    const now = new Date();
    age = now.getFullYear() - dob.getFullYear();
    if (now.getMonth() < dob.getMonth() ||
        (now.getMonth() === dob.getMonth() && now.getDate() < dob.getDate())) age--;
  }
  return {
    displayName: p.displayName || 'Member',
    age,
    city: p.city || null,
    country: p.country || null,
    profession: p.profession || null,
    education: p.education || null,
    maritalStatus: p.maritalStatus || null,
    languages: p.languages || [],
    madhhab: p.madhhab || null,
    revert: p.revert === true,
    prayer: a.prayer || null,
    timeframe: a.timeframe || null,
    ribaDisclosureBadge: u.ribaDisclosureBadge === true,
    bioPrompts: p.bioPrompts || [],
    whyNow: a.shortAnswers?.whyNow || null,
    deenRelationship: a.shortAnswers?.deenRelationship || null,
    photoPrivacy: u.photoPrivacy || 'blur_until_match',
    hasPhotos: (u.photos || []).length > 0,
  };
}

/** A member asks to see the other's private (request_only) photos. */
exports.requestPhotoReveal = onCall({ region: REGION }, async (request) => {
  const uid = requireAuth(request);
  const convId = request.data?.convId;
  const ref = db.doc(`conversations/${convId}`);
  const snap = await ref.get();
  if (!snap.exists || !snap.get('participants').includes(uid)) {
    throw new HttpsError('permission-denied', 'Not your conversation.');
  }
  await ref.update({ [`photoRevealRequests.${uid}`]: true });
  const other = snap.get('participants').find((p) => p !== uid);
  const name = snap.get('profiles')?.[uid]?.displayName || 'Your match';
  await pushTo(other, 'A photo request',
    `${name} has asked to see your photos. Open the conversation to decide.`);
  return { ok: true };
});

// ============================================================
// Email OTP sign-in (Resend). A public alternative to Google that needs
// no deep-linking: send a 6-digit code, verify it, mint a custom token.
// The otp docs live in emailOtps/{sha256(email)} — backend-only (rules
// deny all client access). Codes are stored hashed with a per-code salt.
// ============================================================
const OTP_TTL_MS = 10 * 60 * 1000;      // code lifetime
const OTP_MAX_ATTEMPTS = 5;             // wrong guesses before invalidation
const OTP_MAX_SENDS_PER_HOUR = 5;       // per email, anti-abuse
const OTP_MIN_RESEND_MS = 30 * 1000;    // throttle rapid re-sends

const emailKey = (email) =>
  crypto.createHash('sha256').update(email).digest('hex');
const hashCode = (salt, code) =>
  crypto.createHash('sha256').update(`${salt}:${code}`).digest('hex');
const normalizeEmail = (raw) => String(raw || '').trim().toLowerCase();
const validEmail = (e) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e);

/** Step 1 — generate a code, store its hash, email it via Resend. */
exports.sendEmailOtp = onCall(
  { region: REGION, secrets: [RESEND_API_KEY] },
  async (request) => {
    const email = normalizeEmail(request.data?.email);
    if (!validEmail(email)) {
      throw new HttpsError('invalid-argument', 'Enter a valid email address.');
    }
    const ref = db.doc(`emailOtps/${emailKey(email)}`);
    const now = Date.now();
    let pendingCode;

    // Rate-limit inside a transaction so parallel sends can't race past it.
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const d = snap.exists ? snap.data() : {};
      const windowStart = d.windowStart?.toMillis?.() ?? 0;
      let sends = d.sends || 0;
      if (now - windowStart > 3600 * 1000) sends = 0; // new rolling hour
      const lastSent = d.lastSentAt?.toMillis?.() ?? 0;
      if (now - lastSent < OTP_MIN_RESEND_MS) {
        throw new HttpsError(
          'resource-exhausted', 'Please wait a moment before requesting another code.');
      }
      if (sends >= OTP_MAX_SENDS_PER_HOUR) {
        throw new HttpsError(
          'resource-exhausted', 'Too many codes requested. Try again later.');
      }
      const salt = crypto.randomBytes(16).toString('hex');
      const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
      pendingCode = code;
      tx.set(ref, {
        email,
        codeHash: hashCode(salt, code),
        salt,
        expiresAt: new Date(now + OTP_TTL_MS),
        attempts: 0,
        sends: sends + 1,
        windowStart: sends === 0 ? new Date(now) : (d.windowStart || new Date(now)),
        lastSentAt: new Date(now),
      });
    });

    try {
      await sendOtpEmail(
        RESEND_API_KEY.value(),
        RESEND_FROM,
        email,
        pendingCode,
      );
    } catch (e) {
      console.error('Resend send failed:', e.message);
      throw new HttpsError('internal', 'Could not send the email. Please try again.');
    }
    return { ok: true };
  },
);

/** Step 2 — verify the code, mint a custom token for signInWithCustomToken. */
exports.verifyEmailOtp = onCall({ region: REGION }, async (request) => {
  const email = normalizeEmail(request.data?.email);
  const code = String(request.data?.code || '').trim();
  if (!validEmail(email) || !/^\d{6}$/.test(code)) {
    throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
  }
  const ref = db.doc(`emailOtps/${emailKey(email)}`);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'No code found — request a new one.');
  }
  const d = snap.data();
  if ((d.expiresAt?.toMillis?.() ?? 0) < Date.now()) {
    await ref.delete();
    throw new HttpsError('deadline-exceeded', 'That code expired — request a new one.');
  }
  if ((d.attempts || 0) >= OTP_MAX_ATTEMPTS) {
    await ref.delete();
    throw new HttpsError('resource-exhausted', 'Too many attempts — request a new code.');
  }
  if (hashCode(d.salt, code) !== d.codeHash) {
    await ref.update({ attempts: FieldValue.increment(1) });
    throw new HttpsError('permission-denied', 'Incorrect code. Please try again.');
  }

  // Correct — burn the code and mint a session for this email.
  await ref.delete();
  const auth = getAuth();
  let uid;
  try {
    uid = (await auth.getUserByEmail(email)).uid;
  } catch (_) {
    uid = (await auth.createUser({ email, emailVerified: true })).uid;
  }
  const token = await auth.createCustomToken(uid);
  return { token };
});
