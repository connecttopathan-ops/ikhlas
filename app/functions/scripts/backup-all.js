/**
 * Full logical backup of Firestore + Auth users to local JSON.
 *
 * Why this exists rather than `gcloud firestore export`: the managed export
 * requires billing to be enabled on the project, which is exactly the thing
 * that is broken when you most need a backup. Firestore and Auth both have
 * free-tier quotas, so the Admin SDK can still read them while billing is
 * suspended and Cloud Functions are dead.
 *
 * Recurses subcollections, so the nested read model comes out whole:
 *   matches/{uid}/batches/{istDate}/entries/{otherUid}
 *   conversations/{id}/messages/{id}
 *
 * Auth: these members sign in with Google, Apple or an emailed OTP exchanged
 * for a custom token — there are no passwords in this project, so listUsers()
 * captures everything needed to recreate the accounts (uid, email, provider
 * links, custom claims). No password hashes to carry across.
 *
 * CONTAINS PERSONAL DATA (profiles, ID-verification state, messages). Treat
 * the output as confidential: never commit it, and delete the CI artifact
 * once it is stored somewhere safe.
 *
 * Usage: node scripts/backup-all.js [outDir]
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const outDir = process.argv[2] || 'backup';
let docCount = 0;
let colCount = 0;

/** Firestore values that have no JSON equivalent, tagged so an import can rebuild them. */
function encode(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof admin.firestore.Timestamp) {
    return { __type__: 'timestamp', value: value.toDate().toISOString() };
  }
  if (value instanceof admin.firestore.DocumentReference) {
    return { __type__: 'ref', value: value.path };
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return { __type__: 'geopoint', lat: value.latitude, lng: value.longitude };
  }
  if (Buffer.isBuffer(value)) {
    return { __type__: 'bytes', value: value.toString('base64') };
  }
  if (Array.isArray(value)) return value.map(encode);
  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = encode(v);
    return out;
  }
  return value;
}

/** Depth-first walk of a collection and everything beneath it. */
async function dumpCollection(ref, trail) {
  const snap = await ref.get();
  colCount += 1;
  const docs = {};
  for (const doc of snap.docs) {
    docCount += 1;
    const entry = { data: encode(doc.data()) };
    // A document can hold subcollections while having no fields of its own,
    // so recurse unconditionally rather than only on non-empty documents.
    const subs = await doc.ref.listCollections();
    if (subs.length) {
      entry.collections = {};
      for (const sub of subs) {
        entry.collections[sub.id] = await dumpCollection(sub, `${trail}/${doc.id}/${sub.id}`);
      }
    }
    docs[doc.id] = entry;
  }
  console.log(`  ${trail}: ${snap.size} docs`);
  return docs;
}

async function backupFirestore() {
  console.log('--- firestore ---');
  const roots = await db.listCollections();
  const out = {};
  for (const col of roots) {
    out[col.id] = await dumpCollection(col, col.id);
  }
  return out;
}

async function backupAuth() {
  console.log('--- auth users ---');
  const users = [];
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const u of page.users) {
      users.push({
        uid: u.uid,
        email: u.email || null,
        emailVerified: u.emailVerified,
        displayName: u.displayName || null,
        photoURL: u.photoURL || null,
        phoneNumber: u.phoneNumber || null,
        disabled: u.disabled,
        customClaims: u.customClaims || null,
        metadata: {
          creationTime: u.metadata.creationTime,
          lastSignInTime: u.metadata.lastSignInTime,
        },
        providerData: u.providerData.map((p) => ({
          providerId: p.providerId,
          uid: p.uid,
          email: p.email || null,
          displayName: p.displayName || null,
        })),
      });
    }
    pageToken = page.pageToken;
  } while (pageToken);
  console.log(`  ${users.length} users`);
  return users;
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });

  const firestore = await backupFirestore();
  fs.writeFileSync(
    path.join(outDir, 'firestore.json'),
    JSON.stringify(firestore, null, 2),
  );

  const users = await backupAuth();
  fs.writeFileSync(path.join(outDir, 'auth-users.json'), JSON.stringify(users, null, 2));

  const manifest = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || null,
    takenAt: new Date().toISOString(),
    collections: colCount,
    documents: docCount,
    users: users.length,
  };
  fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));

  console.log('--- done ---');
  console.log(JSON.stringify(manifest, null, 2));
})().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
