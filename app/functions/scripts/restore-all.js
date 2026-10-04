/**
 * Restores a backup-all.js dump into the project the credentials point at.
 *
 * Counterpart to scripts/backup-all.js. Used to move the project to a new
 * Firebase project (new Google account / clean payments profile) without
 * losing members or their data.
 *
 * Auth users are imported WITH THEIR ORIGINAL UIDs. That is the part that
 * makes the whole migration work: every Firestore document in this product is
 * keyed by uid (users/{uid}, matches/{uid}/batches/..., the conversations
 * profiles map), so preserving uids means the imported data lines up with the
 * imported accounts and nobody loses their profile, matches or chats.
 * providerData is carried across so Google and Apple sign-in resolve to the
 * same account rather than creating a duplicate. There are no password hashes
 * in this project (Google, Apple, or an emailed OTP exchanged for a custom
 * token), so nothing is lost by not carrying them.
 *
 * Usage:
 *   node scripts/restore-all.js <backupDir> [--dry-run] [--only=firestore|auth]
 *
 * Refuses to run against a project that already has data unless --force is
 * given, so it cannot quietly overwrite a live project by mistake.
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const args = process.argv.slice(2);
const dir = args.find((a) => !a.startsWith('--'));
const dryRun = args.includes('--dry-run');
const force = args.includes('--force');
const onlyArg = args.find((a) => a.startsWith('--only='));
const only = onlyArg ? onlyArg.split('=')[1] : 'all';

if (!dir) {
  console.error('usage: node scripts/restore-all.js <backupDir> [--dry-run] [--only=firestore|auth] [--force]');
  process.exit(1);
}

let written = 0;
let usersWritten = 0;

/** Inverse of backup-all.js encode() — rebuild the Firestore-native types. */
function decode(value) {
  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) return value.map(decode);
  if (typeof value === 'object') {
    switch (value.__type__) {
      case 'timestamp':
        return admin.firestore.Timestamp.fromDate(new Date(value.value));
      case 'ref':
        return db.doc(value.value);
      case 'geopoint':
        return new admin.firestore.GeoPoint(value.lat, value.lng);
      case 'bytes':
        return Buffer.from(value.value, 'base64');
      default: {
        const out = {};
        for (const [k, v] of Object.entries(value)) out[k] = decode(v);
        return out;
      }
    }
  }
  return value;
}

/**
 * Walks the dump depth-first. Batched in chunks well under Firestore's
 * 500-op write limit, counting each document once.
 */
async function restoreCollection(parentPath, colId, docs) {
  const entries = Object.entries(docs);
  for (let i = 0; i < entries.length; i += 400) {
    const chunk = entries.slice(i, i + 400);
    const batch = db.batch();
    for (const [docId, entry] of chunk) {
      const ref = db.doc(`${parentPath ? `${parentPath}/` : ''}${colId}/${docId}`);
      batch.set(ref, decode(entry.data || {}));
      written += 1;
    }
    if (!dryRun) await batch.commit();
  }
  // Subcollections after the parents exist, so the tree is never orphaned.
  for (const [docId, entry] of entries) {
    if (!entry.collections) continue;
    for (const [subId, subDocs] of Object.entries(entry.collections)) {
      await restoreCollection(
        `${parentPath ? `${parentPath}/` : ''}${colId}/${docId}`,
        subId,
        subDocs,
      );
    }
  }
}

async function restoreFirestore() {
  const file = path.join(dir, 'firestore.json');
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));

  if (!force && !dryRun) {
    // Guard: never silently merge a dump into a project that already holds data.
    const existing = await db.listCollections();
    if (existing.length) {
      throw new Error(
        `target project already has ${existing.length} root collections ` +
        `(${existing.map((c) => c.id).join(', ')}). Pass --force only if you ` +
        'genuinely intend to overwrite them.',
      );
    }
  }

  console.log('--- firestore ---');
  for (const [colId, docs] of Object.entries(data)) {
    await restoreCollection('', colId, docs);
    console.log(`  ${colId}: done`);
  }
}

async function restoreAuth() {
  const users = JSON.parse(fs.readFileSync(path.join(dir, 'auth-users.json'), 'utf8'));
  console.log('--- auth users ---');
  for (let i = 0; i < users.length; i += 500) {
    const chunk = users.slice(i, i + 500).map((u) => ({
      uid: u.uid, // preserving this is what keeps Firestore data attached
      email: u.email || undefined,
      emailVerified: !!u.emailVerified,
      displayName: u.displayName || undefined,
      photoURL: u.photoURL || undefined,
      phoneNumber: u.phoneNumber || undefined,
      disabled: !!u.disabled,
      customClaims: u.customClaims || undefined,
      providerData: (u.providerData || [])
        // Firebase rejects a provider entry without a uid.
        .filter((p) => p.providerId && p.uid)
        .map((p) => ({
          providerId: p.providerId,
          uid: p.uid,
          email: p.email || undefined,
          displayName: p.displayName || undefined,
        })),
    }));
    if (dryRun) {
      usersWritten += chunk.length;
      continue;
    }
    const res = await admin.auth().importUsers(chunk);
    usersWritten += res.successCount;
    if (res.failureCount) {
      for (const err of res.errors) {
        console.error(`  user ${chunk[err.index].uid}: ${err.error.message}`);
      }
    }
  }
  console.log(`  ${usersWritten}/${users.length} users imported`);
}

(async () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  const target = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || '(unknown)';
  console.log(`restoring backup of ${manifest.project} (${manifest.documents} docs, ` +
    `${manifest.users} users, taken ${manifest.takenAt})`);
  console.log(`into project: ${target}${dryRun ? '  [DRY RUN]' : ''}`);
  if (manifest.project === target && !force) {
    throw new Error('target project is the SAME as the backup source; refusing to restore onto itself');
  }

  if (only === 'all' || only === 'auth') await restoreAuth();
  if (only === 'all' || only === 'firestore') await restoreFirestore();

  console.log('--- done ---');
  console.log(`documents: ${written}, users: ${usersWritten}${dryRun ? ' (nothing written)' : ''}`);
})().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
