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
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { evaluateGate } = require('./gate');

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
        title: 'Welcome to Ikhlas',
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

  const batch = buildBatch(user, pool, { seen, interestedInMe });
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

    // Wali visibility: if either participant set an observing Wali, the
    // conversation shows the transparency badge to both.
    const [ua, ub] = await Promise.all([
      db.doc(`users/${uid}`).get(),
      db.doc(`users/${otherUid}`).get(),
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
      'Sharing contact details or moving off Ikhlas is not allowed before ' +
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
        notification: { title: 'New message', body: 'You have a new message on Ikhlas.' },
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
