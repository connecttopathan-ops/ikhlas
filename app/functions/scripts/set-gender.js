/**
 * Moderator correction: set a member's gender (male|female) by email.
 * Updates the authoritative users/{uid}.gender field the app reads for
 * routing, the wali flow, and the matching pool. Existing match batches
 * regenerate on the next daily run.
 *
 * Env: SET_GENDER_EMAIL, SET_GENDER_VALUE (male|female)
 */
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function main() {
  const email = String(process.env.SET_GENDER_EMAIL || '').trim().toLowerCase();
  const gender = String(process.env.SET_GENDER_VALUE || '').trim().toLowerCase();
  if (!email) throw new Error('SET_GENDER_EMAIL not set');
  if (gender !== 'male' && gender !== 'female') {
    throw new Error('SET_GENDER_VALUE must be "male" or "female"');
  }
  const uid = (await admin.auth().getUserByEmail(email)).uid;
  const ref = db.doc(`users/${uid}`);
  const snap = await ref.get();
  if (!snap.exists) throw new Error(`no users/${uid} doc`);
  const prev = snap.get('gender');
  await ref.set({ gender }, { merge: true });
  console.log(`gender for ${email} (${uid}): ${prev} -> ${gender}`);
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
