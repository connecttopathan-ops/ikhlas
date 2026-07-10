const { test } = require('node:test');
const assert = require('node:assert');
const { hardFilterPass, scorePair, buildBatch } = require('./matching');

const NOW = new Date('2026-07-05T12:00:00Z');

function user(id, over = {}) {
  return {
    _id: id,
    status: 'approved',
    profileComplete: true,
    gender: 'male',
    dob: '1998-01-01',
    lastActiveAt: '2026-07-04T00:00:00Z',
    profile: {
      maritalStatus: 'never_married',
      hasChildren: false,
      willingToRelocate: true,
      city: 'Hyderabad',
      country: 'India',
      languages: ['Urdu', 'English'],
      ...over.profile,
    },
    preferences: {
      ageMin: 20,
      ageMax: 40,
      acceptDivorced: true,
      acceptWidowed: true,
      acceptChildren: true,
      relocationRequired: false,
      ...over.preferences,
    },
    answers: { prayer: 'five_daily', timeframe: '6_12m', ...over.answers },
    ...Object.fromEntries(
      Object.entries(over).filter(
        ([k]) => !['profile', 'preferences', 'answers'].includes(k)
      )
    ),
  };
}

const HIM = user('him');
const HER = user('her', { gender: 'female', dob: '2000-05-01' });

test('opposite genders within mutual filters pass', () => {
  assert.ok(hardFilterPass(HIM, HER, NOW));
});

test('same gender never matches', () => {
  assert.ok(!hardFilterPass(HIM, user('him2'), NOW));
});

test('age filters are mutual', () => {
  const picky = user('picky', {
    gender: 'female',
    dob: '2000-05-01',
    preferences: { ageMax: 25 },
  });
  // HIM is 28 in 2026 → picky rejects him → no match either direction
  assert.ok(!hardFilterPass(HIM, picky, NOW));
});

test('children openness respected bidirectionally', () => {
  const withKids = user('kids', {
    gender: 'female',
    dob: '1995-01-01',
    profile: { hasChildren: true },
  });
  const noKidsPlease = user('nkp', { preferences: { acceptChildren: false } });
  assert.ok(!hardFilterPass(noKidsPlease, withKids, NOW));
  assert.ok(hardFilterPass(HIM, withKids, NOW));
});

test('relocationRequired demands willingToRelocate', () => {
  const anchored = user('anchor', {
    gender: 'female',
    dob: '1999-01-01',
    profile: { willingToRelocate: false },
  });
  const mustMove = user('mm', { preferences: { relocationRequired: true } });
  assert.ok(!hardFilterPass(mustMove, anchored, NOW));
});

test('deen alignment outweighs geography', () => {
  const sameDeenFar = user('a', {
    gender: 'female',
    dob: '2000-01-01',
    profile: { city: 'Delhi', languages: ['Hindi'] },
  });
  const sameCityLaxDeen = user('b', {
    gender: 'female',
    dob: '2000-01-01',
    answers: { prayer: 'most' },
    profile: { languages: ['Hindi'] },
  });
  const s1 = scorePair(HIM, sameDeenFar, NOW).score;
  const s2 = scorePair(HIM, sameCityLaxDeen, NOW).score;
  assert.ok(s1 > s2, `deen ${s1} should beat city ${s2}`);
});

test('batch caps at 5, excludes seen, surfaces interested-in-me first', () => {
  const pool = Array.from({ length: 8 }, (_, i) =>
    user(`w${i}`, { gender: 'female', dob: '2000-01-01' })
  );
  const batch = buildBatch(HIM, pool, {
    seen: new Set(['w0']),
    interestedInMe: new Set(['w7']),
    now: NOW,
  });
  assert.equal(batch.length, 5);
  assert.ok(!batch.some((e) => e.candidate._id === 'w0'), 'seen excluded');
  assert.equal(batch[0].candidate._id, 'w7', 'interested-in-me first');
});

test('non-approved and incomplete profiles never enter a batch', () => {
  const pool = [
    user('pending', { gender: 'female', dob: '2000-01-01', status: 'under_review' }),
    user('bare', { gender: 'female', dob: '2000-01-01', profileComplete: false }),
  ];
  assert.equal(buildBatch(HIM, pool, { now: NOW }).length, 0);
});

test('compatibility highlights are human sentences, max 3', () => {
  const { why } = scorePair(HIM, HER, NOW);
  assert.ok(why.length > 0 && why.length <= 3);
  assert.ok(why.some((w) => w.includes('five daily')));
});

// ---- PRD v1.2: bands, divergence, exposure cap, hygiene, diaspora ----

test('every pair carries exactly one honest divergence string', () => {
  const { divergence } = scorePair(HIM, HER, NOW);
  assert.equal(typeof divergence, 'string');
  assert.ok(divergence.length > 0);
});

test('a strongly aligned pair gets a band and is shown', () => {
  const batch = buildBatch(HIM, [HER], { now: NOW });
  assert.equal(batch.length, 1);
  assert.ok(['strong', 'good', 'some'].includes(batch[0].band));
});

test('below-threshold pairs are never shown (band null → filtered)', () => {
  const lowHer = user('low', {
    gender: 'female',
    dob: '2000-05-01',
    lastActiveAt: '2026-06-25T00:00:00Z', // >7d: no freshness boost; <30d: not stale
    profile: { city: 'Delhi', languages: ['Tamil'], willingToRelocate: false },
    // 'exploring' isn't in the timeframe order → no timeframe score; no shared
    // language; different city → total stays below the "some" threshold.
    answers: { prayer: 'working', timeframe: 'exploring' },
  });
  const batch = buildBatch(HIM, [lowHer], { now: NOW });
  assert.equal(batch.length, 0);
});

test('exposure cap removes a profile once it has filled its daily quota', () => {
  const atCap = buildBatch(HIM, [HER], {
    now: NOW,
    exposure: new Map([['her', 15]]),
  });
  assert.equal(atCap.length, 0);
  const underCap = buildBatch(HIM, [HER], {
    now: NOW,
    exposure: new Map([['her', 14]]),
  });
  assert.equal(underCap.length, 1);
});

test('inactive >30 days drops out of circulation', () => {
  const staleHer = user('stale', {
    gender: 'female',
    dob: '2000-05-01',
    lastActiveAt: '2026-05-01T00:00:00Z', // >30d before NOW (2026-07-05)
  });
  assert.equal(buildBatch(HIM, [staleHer], { now: NOW }).length, 0);
});

test('country is open by default but a hard filter when the user opts out', () => {
  const abroadHer = user('abroad', {
    gender: 'female',
    dob: '2000-05-01',
    profile: { country: 'UAE', city: 'Dubai' },
  });
  // Default (openToSpouseAbroad unset) → diaspora match allowed.
  assert.ok(hardFilterPass(HIM, abroadHer, NOW));
  // Opted out → different country is rejected.
  const himClosed = user('himClosed', {
    preferences: { openToSpouseAbroad: false },
  });
  assert.ok(!hardFilterPass(himClosed, abroadHer, NOW));
});
