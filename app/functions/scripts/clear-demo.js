/**
 * Remove the screenshot demo data seeded by seed-demo.js.
 *
 * Deletes, in order:
 *   · every conversation flagged {demo:true} (messages subcollection first)
 *   · demo_* entries and seen markers inside the member's match batches
 *   · every users/{id} doc flagged {demo:true}
 *
 * Everything it touches was created by the seeder and carries either a
 * `demo: true` flag or a `demo_` id prefix, so real members and real
 * conversations are never at risk.
 *
 * Env: CLEAR_DEMO_EMAIL — the member whose match batches were seeded.
 */
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function deleteConversations() {
  const snap = await db.collection('conversations').where('demo', '==', true).get();
  for (const conv of snap.docs) {
    const msgs = await conv.ref.collection('messages').get();
    await Promise.all(msgs.docs.map((m) => m.ref.delete()));
    await conv.ref.delete();
    console.log(`  deleted conversation ${conv.id} (${msgs.size} messages)`);
  }
  return snap.size;
}

async function deleteBatchEntries(uid) {
  let entries = 0;
  let seen = 0;
  const batches = await db.collection(`matches/${uid}/batches`).get();
  for (const b of batches.docs) {
    const es = await b.ref.collection('entries').get();
    for (const e of es.docs) {
      if (!e.id.startsWith('demo_')) continue;
      await e.ref.delete();
      entries++;
    }
  }
  const seenSnap = await db.collection(`matches/${uid}/seen`).get();
  for (const s of seenSnap.docs) {
    if (!s.id.startsWith('demo_')) continue;
    await s.ref.delete();
    seen++;
  }
  return { entries, seen };
}

async function deleteDemoUsers() {
  const snap = await db.collection('users').where('demo', '==', true).get();
  for (const d of snap.docs) {
    await d.ref.delete();
    console.log(`  deleted member ${d.id}`);
  }
  return snap.size;
}

async function main() {
  const email = String(process.env.CLEAR_DEMO_EMAIL || '').trim().toLowerCase();
  if (!email) throw new Error('CLEAR_DEMO_EMAIL not set');
  const uid = (await admin.auth().getUserByEmail(email)).uid;
  console.log(`clearing demo data seeded for ${email} (${uid})`);

  const convs = await deleteConversations();
  const { entries, seen } = await deleteBatchEntries(uid);
  const users = await deleteDemoUsers();

  console.log(
    `demo cleanup complete: ${users} members, ${entries} match entries, ` +
    `${seen} seen markers, ${convs} conversations`
  );
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
