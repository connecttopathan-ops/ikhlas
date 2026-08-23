/**
 * Moderator override: approve a member by email (rescinds a prior
 * soft_rejected/rejected gate decision). Sets users/{uid}.status = 'approved'
 * and marks the application decision approved; the notifyDecision trigger then
 * finalizes ID + sends the approval notification. The applicant proceeds to
 * build their full profile as normal.
 *
 * Note: a soft-rejected applicant's government-ID was already purged from
 * quarantine, so this override approves without an ID on file.
 *
 * Env: APPROVE_MEMBER_EMAIL
 * Run: APPROVE_MEMBER_EMAIL=you@example.com node scripts/approve-member.js
 */
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
const { FieldValue } = admin.firestore;

async function main() {
  const email = String(process.env.APPROVE_MEMBER_EMAIL || '').trim().toLowerCase();
  if (!email) throw new Error('APPROVE_MEMBER_EMAIL not set');
  const user = await admin.auth().getUserByEmail(email);
  const uid = user.uid;

  const userSnap = await db.doc(`users/${uid}`).get();
  if (!userSnap.exists) throw new Error(`no users/${uid} doc`);
  const prev = userSnap.get('status');
  console.log(`approving ${email} (${uid}) — current status: ${prev}`);

  // Flip status → approved (notifyDecision finalizes ID + notifies).
  await db.doc(`users/${uid}`).set({ status: 'approved' }, { merge: true });

  // Reflect the override on the application record (if present).
  const appRef = db.doc(`applications/${uid}`);
  if ((await appRef.get()).exists) {
    await appRef.set({
      decision: 'approved',
      decidedAt: FieldValue.serverTimestamp(),
      decidedBy: 'moderator_override',
    }, { merge: true });
  }

  console.log(`done — ${email} status ${prev} -> approved`);
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
