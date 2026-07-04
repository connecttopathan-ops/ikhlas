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
