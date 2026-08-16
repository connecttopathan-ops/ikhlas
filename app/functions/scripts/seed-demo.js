/**
 * One-off DEMO seeder for Play Store screenshots.
 *
 * Creates a set of (female) demo match entries in today's batch and one live
 * conversation with a short transcript, for the member whose email is passed
 * as SEED_DEMO_EMAIL. Everything is denormalized exactly as the server would
 * write it, so the match cards and chat render from these docs alone (no auth
 * users or served photos required — cards fall back to the girih silhouette).
 *
 * Idempotent: fixed demo ids, so re-running overwrites rather than duplicates.
 * Demo data only — safe to delete afterwards (ids are prefixed `demo_`).
 *
 * Run:  SEED_DEMO_EMAIL=you@example.com node scripts/seed-demo.js
 */
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
const { Timestamp, FieldValue } = admin.firestore;

// Today's IST calendar date (YYYY-MM-DD) — matches the app's todayIst().
function istDateKey() {
  const ist = new Date(Date.now() + 5.5 * 3600 * 1000);
  const y = ist.getUTCFullYear();
  const m = String(ist.getUTCMonth() + 1).padStart(2, '0');
  const d = String(ist.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// Female demo profiles (band drives ordering: strong > good > some).
const DEMOS = [
  {
    id: 'demo_aisha', displayName: 'Aisha', age: 26, city: 'Hyderabad',
    country: 'India', profession: 'Primary school teacher', education: "Bachelor's in Education",
    band: 'strong', score: 0.94, timeframe: '6m',
    compatibility: ['You both pray all five daily', 'Both want to marry within 6 months', 'Both Hanafi'],
    divergence: 'She would prefer to live in a joint family; you noted a preference for a separate home.',
    islamicPractice: 'I pray all five on time, in sha Allah, and want a home built on the Sunnah.',
    lookingForSpouse: 'A practising husband who leads with gentleness, sincerity and deen.',
    languages: ['Urdu', 'English', 'Hindi'], madhhab: 'hanafi', sect: 'sunni',
    hijab: 'always', maritalStatus: 'never_married', heightCm: 162, build: 'average',
    quranEngagement: 'reads_daily', fasting: 'beyond_ramadan_sometimes',
  },
  {
    id: 'demo_maryam', displayName: 'Maryam', age: 28, city: 'Bengaluru',
    country: 'India', profession: 'Doctor (GP)', education: 'MBBS',
    band: 'strong', score: 0.91, timeframe: '6_12m',
    compatibility: ['You both pray all five daily', 'Both value seeking knowledge', 'Similar family values'],
    divergence: 'She is open to relocating abroad; you preferred to stay in India for now.',
    islamicPractice: 'Deen comes first for me — I try to keep my prayers and character in check.',
    lookingForSpouse: 'Someone God-conscious, kind to his parents, and serious about nikah.',
    languages: ['English', 'Kannada', 'Urdu'], madhhab: 'hanafi', sect: 'sunni',
    hijab: 'always', maritalStatus: 'never_married', heightCm: 165, build: 'slim',
    quranEngagement: 'reads_weekly', fasting: 'ramadan_only',
  },
  {
    id: 'demo_fatima', displayName: 'Fatima', age: 24, city: 'Chennai',
    country: 'India', profession: 'Software engineer', education: "Bachelor's in Computer Science",
    band: 'good', score: 0.83, timeframe: '6m',
    compatibility: ['You both pray all five daily', 'Both want to marry soon', 'Both value modesty'],
    divergence: 'She memorises Qur’an actively; you described yourself as a regular reader.',
    islamicPractice: 'I love the Qur’an and try to live by what I learn, however small.',
    lookingForSpouse: 'A husband with good akhlaq who fears Allah in private and public.',
    languages: ['Tamil', 'English'], madhhab: 'shafii', sect: 'sunni',
    hijab: 'always', maritalStatus: 'never_married', heightCm: 158, build: 'petite',
    quranEngagement: 'memorising', fasting: 'beyond_ramadan_regularly',
  },
  {
    id: 'demo_khadija', displayName: 'Khadija', age: 29, city: 'Mumbai',
    country: 'India', profession: 'Pharmacist', education: 'PharmD',
    band: 'good', score: 0.79, timeframe: '6_12m',
    compatibility: ['You both pray all five daily', 'Both previously married, no children', 'Both Hanafi'],
    divergence: 'She would like to continue working after marriage; confirm this suits you.',
    islamicPractice: 'After a difficult chapter, my deen is what steadied me. I want a calm, God-centred home.',
    lookingForSpouse: 'A mature, patient man who values a second chance built on taqwa.',
    languages: ['Hindi', 'English', 'Marathi'], madhhab: 'hanafi', sect: 'sunni',
    hijab: 'always', maritalStatus: 'divorced', heightCm: 160, build: 'average',
    quranEngagement: 'reads_weekly', fasting: 'ramadan_only',
  },
  {
    id: 'demo_zainab', displayName: 'Zainab', age: 25, city: 'Pune',
    country: 'India', profession: 'Accountant', education: "Bachelor's in Commerce",
    band: 'some', score: 0.66, timeframe: '12_24m',
    compatibility: ['You both pray most prayers', 'Both from similar backgrounds'],
    divergence: 'Her timeframe is longer than yours — she is looking over the next 1–2 years.',
    islamicPractice: 'I am growing in my practice and want a spouse who helps me get closer to Allah.',
    lookingForSpouse: 'A patient, encouraging husband who leads the family in deen.',
    languages: ['Marathi', 'Hindi', 'English'], madhhab: 'hanafi', sect: 'sunni',
    hijab: 'sometimes', maritalStatus: 'never_married', heightCm: 163, build: 'average',
    quranEngagement: 'reads_sometimes', fasting: 'ramadan_only',
  },
];

function entryDoc(p) {
  return {
    displayName: p.displayName,
    age: p.age,
    gender: 'female',
    city: p.city,
    country: p.country,
    profession: p.profession,
    education: p.education,
    languages: p.languages,
    maritalStatus: p.maritalStatus,
    revert: false,
    height: p.heightCm,
    build: p.build,
    hijab: p.hijab,
    sect: p.sect,
    madhhab: p.madhhab,
    prayer: p.band === 'some' ? 'most' : 'five_daily',
    timeframe: p.timeframe,
    quranEngagement: p.quranEngagement,
    fasting: p.fasting,
    islamicPractice: p.islamicPractice,
    lookingForSpouse: p.lookingForSpouse,
    lookingForFamily: 'A warm, practising family that values deen over dunya.',
    aboutFamily: 'Close-knit, practising family. My father and brothers are supportive of the process.',
    livingArrangement: 'family_home',
    deenRelationship: 'My relationship with Allah is the centre of my life, and I want a marriage that strengthens it.',
    ribaDisclosureBadge: true,
    hasPhotos: false,
    photoVisibility: 'on_mutual_blur',
    compatibility: p.compatibility,
    divergence: p.divergence,
    band: p.band,
    score: p.score,
    action: null,
    actionAt: null,
  };
}

async function main() {
  const email = String(process.env.SEED_DEMO_EMAIL || '').trim().toLowerCase();
  if (!email) throw new Error('SEED_DEMO_EMAIL not set');
  const me = (await admin.auth().getUserByEmail(email)).uid;
  const date = istDateKey();
  console.log(`seeding demo for ${email} (${me}), batch date ${date}`);

  // 1) Match batch + entries
  const batchRef = db.doc(`matches/${me}/batches/${date}`);
  await batchRef.set({ date, count: DEMOS.length, generatedAt: FieldValue.serverTimestamp() });
  for (const p of DEMOS) {
    await batchRef.collection('entries').doc(p.id).set(entryDoc(p));
    // Minimal member doc for safety (not strictly read by the card).
    await db.doc(`users/${p.id}`).set({
      status: 'approved', profileComplete: true, gender: 'female',
      displayName: p.displayName,
      profile: { residence: { city: p.city, country: p.country }, photoVisibility: 'on_mutual_blur' },
      demo: true,
    }, { merge: true });
  }
  console.log(`  wrote ${DEMOS.length} match entries`);

  // 2) One live conversation with Aisha (the top match)
  const other = DEMOS[0];
  const convId = [me, other.id].sort().join('_');
  const base = Date.now() - 26 * 60 * 1000; // started ~26 min ago
  const T = (minsAfter) => Timestamp.fromDate(new Date(base + minsAfter * 60 * 1000));
  const msgs = [
    { system: true, from: me, text: 'You both expressed interest. This conversation is guarded — please keep it respectful and to the point of nikah.', at: T(0) },
    { from: other.id, text: 'Assalamu alaikum. JazakAllah khair for your interest — I read your profile and appreciated your answers on the deen section.', at: T(1) },
    { from: me, text: "Wa alaikum assalam wa rahmatullah. BarakAllahu feek. Your practice and family values stood out to me as well.", at: T(4) },
    { from: other.id, text: 'Alhamdulillah. May I ask what your timeframe for marriage looks like, in sha Allah?', at: T(7) },
    { from: me, text: "In sha Allah within six months. I'd like to involve both our families early so it's done the right way.", at: T(10) },
    { from: other.id, text: 'That aligns with mine, alhamdulillah. I will speak to my wali and we can take the next step. BarakAllahu feek.', at: T(13) },
  ];
  const last = msgs[msgs.length - 1];
  await db.doc(`conversations/${convId}`).set({
    participants: [me, other.id],
    stage: 'intro',
    frozen: false,
    waliObserving: false,
    adabAcknowledged: { [me]: true, [other.id]: true },
    profiles: {
      [me]: { displayName: 'You', gender: 'male', hasPhotos: false, photoVisibility: 'on_mutual_blur' },
      [other.id]: { displayName: other.displayName, gender: 'female', hasPhotos: false, photoVisibility: 'on_mutual_blur' },
    },
    photoReveal: { [me]: false, [other.id]: false },
    createdAt: T(0),
    lastMessageAt: last.at,
    lastMessageText: last.text,
    lastMessageFrom: last.from,
    readUpTo: { [me]: last.at, [other.id]: last.at },
    deliveredUpTo: { [me]: last.at, [other.id]: last.at },
    demo: true,
  });
  // Clear any prior demo messages, then write the transcript.
  const existing = await db.collection(`conversations/${convId}/messages`).get();
  await Promise.all(existing.docs.map((d) => d.ref.delete()));
  let i = 0;
  for (const m of msgs) {
    await db.doc(`conversations/${convId}/messages/demo_msg_${i++}`).set(m);
  }
  console.log(`  wrote conversation ${convId} with ${msgs.length} messages`);
  console.log('demo seed complete');
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
