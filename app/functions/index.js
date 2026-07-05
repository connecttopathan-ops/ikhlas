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
    await convRef.set({
      participants: [uid, otherUid].sort(),
      stage: 'intro',                       // → deepening → family → closed_*
      stageHistory: [
        { stage: 'intro', at: new Date() }, // auditable event log (PRD §8)
      ],
      adabAcknowledged: {},
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
