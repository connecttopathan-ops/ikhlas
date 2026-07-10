/**
 * Matching engine v1 — deterministic, no ML (PRD v1.2 §4.2).
 * Pure functions: user snapshots in, ranked batch out. No I/O.
 *
 * Model: curated daily batch of at most 5, NOT swiping.
 *   1. Hard filters first, MUTUAL (both directions must accept). Never relaxed.
 *   2. Scoring — deen-practice alignment weighted heaviest. Section F
 *      (deenDetail) is what gives that weight variance to bite on.
 *   3. Band (Strong/Good/Some) + reasons + exactly one honest divergence.
 *   4. Rank by expressed-interest → band → recency (never raw score).
 *   5. Exposure cap so a few profiles don't consume every batch.
 *
 * Data principle (PRD §0): income and residency are NEVER scored here.
 * Expectation *alignment* is scored; rupees are not.
 */

const BATCH_LIMIT = 5;

const DEFAULT_CFG = {
  exposureCapPerDay: 15, // max batches one profile may appear in per day
  bandStrong: 70,
  bandGood: 45,
  bandSome: 25, // below this a pair is never shown
};

const TIMEFRAME_ORDER = { '6m': 0, '6_12m': 1, '12_24m': 2 };
const TIMEFRAME_LABEL = {
  '6m': 'within 6 months',
  '6_12m': '6–12 months',
  '12_24m': '12–24 months',
};
const FINANCIAL_LABEL = {
  comfortable_provision: 'comfortable provision',
  modest_is_fine: 'a modest life is enough',
  build_together: 'building together',
};

function ageOf(user, now = new Date()) {
  if (!user.dob) return null;
  const dob = user.dob instanceof Date ? user.dob : new Date(user.dob);
  let age = now.getFullYear() - dob.getFullYear();
  if (
    now.getMonth() < dob.getMonth() ||
    (now.getMonth() === dob.getMonth() && now.getDate() < dob.getDate())
  ) {
    age--;
  }
  return age;
}

/** One direction of acceptance: does `seeker` accept `candidate`? */
function accepts(seeker, candidate, now) {
  const p = seeker.preferences || {};
  const cAge = ageOf(candidate, now);
  if (cAge == null) return false;
  if (p.ageMin != null && cAge < p.ageMin) return false;
  if (p.ageMax != null && cAge > p.ageMax) return false;

  const marital = candidate.profile?.maritalStatus;
  if (marital === 'divorced' && p.acceptDivorced === false) return false;
  if (marital === 'widowed' && p.acceptWidowed === false) return false;
  if (candidate.profile?.hasChildren === true && p.acceptChildren === false) {
    return false;
  }
  if (
    p.relocationRequired === true &&
    candidate.profile?.willingToRelocate !== true
  ) {
    return false;
  }

  // Country of residence — a hard filter ONLY when the user opts in (§0/§4.2).
  // Diaspora ↔ India is a real match, so the default (undefined/true) is open.
  const sCountry = seeker.profile?.country;
  const cCountry = candidate.profile?.country;
  if (p.openToSpouseAbroad === false && sCountry && cCountry &&
      sCountry !== cCountry) {
    return false;
  }
  if (Array.isArray(p.countries) && p.countries.length > 0 && cCountry &&
      !p.countries.includes(cCountry)) {
    return false;
  }
  return true;
}

/** Mutual hard filters (PRD: both users' filters respected bidirectionally). */
function hardFilterPass(a, b, now = new Date()) {
  if (!a.gender || !b.gender || a.gender === b.gender) return false;
  return accepts(a, b, now) && accepts(b, a, now);
}

/**
 * Deterministic score + reasons. Deen alignment heaviest, and Section F
 * (deenDetail) supplies the variance the approved pool otherwise lacks.
 * `a`/`b` are pool snapshots with {profile, preferences, answers, deenDetail}.
 */
function scorePair(a, b, now = new Date()) {
  let score = 0;
  const why = [];

  // --- Deen practice (heaviest) ---
  const pa = a.answers?.prayer;
  const pb = b.answers?.prayer;
  if (pa && pa === pb) {
    score += 30;
    if (pa === 'five_daily') why.push('You both pray five daily');
    else why.push('Similar prayer consistency');
  } else if (
    (pa === 'five_daily' && pb === 'most') ||
    (pa === 'most' && pb === 'five_daily')
  ) {
    score += 18;
  } else {
    score += 6;
  }

  // --- Section F deen detail (the deen-variance signal) ---
  const da = a.deenDetail || {};
  const db_ = b.deenDetail || {};
  if (da.quran && da.quran === db_.quran) {
    score += 10;
    if (da.quran === 'hafiz') why.push('You are both huffaz, mashaAllah');
  } else if (
    (da.quran === 'hafiz' && db_.quran === 'regular') ||
    (da.quran === 'regular' && db_.quran === 'hafiz')
  ) {
    score += 5;
  }
  if (da.islamicStudy && da.islamicStudy === db_.islamicStudy) score += 7;
  if (da.fastingBeyondRamadan && da.fastingBeyondRamadan === db_.fastingBeyondRamadan) {
    score += 6;
    if (da.fastingBeyondRamadan === 'regularly') {
      why.push('You both fast beyond Ramadan');
    }
  }

  // --- Timeframe alignment ---
  const ta = TIMEFRAME_ORDER[a.answers?.timeframe];
  const tb = TIMEFRAME_ORDER[b.answers?.timeframe];
  if (ta != null && tb != null) {
    const d = Math.abs(ta - tb);
    score += d === 0 ? 20 : d === 1 ? 12 : 5;
    if (d === 0) why.push('Same nikah timeframe');
  }

  // --- Financial-expectation ALIGNMENT (never income; §0) ---
  const fa = a.profile?.financialExpectation;
  const fb = b.profile?.financialExpectation;
  if (fa && fb && fa === fb) {
    score += 8;
    if (fa === 'modest_is_fine') why.push('Both content with a modest life');
  }

  // --- Shared language ---
  const la = new Set(a.profile?.languages || []);
  const shared = (b.profile?.languages || []).filter((l) => la.has(l));
  if (shared.length > 0) {
    score += 15;
    why.push(`You both speak ${shared[0]}`);
  }

  // --- Geography ---
  if (a.profile?.city && a.profile.city === b.profile?.city) {
    score += 10;
    why.push(`Both in ${a.profile.city}`);
  } else if (a.profile?.country && a.profile.country === b.profile?.country) {
    score += 5;
  }

  // --- Madhhab affinity (soft +10, never a hard filter — §0) ---
  if (a.profile?.madhhab && a.profile.madhhab === b.profile?.madhhab) {
    score += 10;
    why.push('Same madhhab');
  }

  // --- Relocation openness pairs well ---
  if (a.profile?.willingToRelocate && b.profile?.willingToRelocate) {
    score += 5;
    why.push('Both open to relocating');
  }

  // --- Freshness ---
  const last = b.lastActiveAt ? new Date(b.lastActiveAt) : null;
  if (last && now - last < 7 * 24 * 3600 * 1000) score += 10;

  return { score, why: why.slice(0, 3), divergence: honestDivergence(a, b) };
}

/**
 * Exactly one honest divergence, from `a`'s point of view about `b`
 * (PRD §4.2 — "one honest divergence, always"). Priority order picks the
 * most decision-relevant real difference; a soft line is the last resort.
 */
function honestDivergence(a, b) {
  const ap = a.profile || {};
  const bp = b.profile || {};

  // 1. Relocation / city
  if (ap.city && bp.city && ap.city !== bp.city) {
    if (ap.willingToRelocate === true && bp.willingToRelocate !== true) {
      return `You're open to relocating; they'd prefer to stay in ${bp.city}`;
    }
    if (bp.willingToRelocate === true && ap.willingToRelocate !== true) {
      return `They're open to relocating; you'd prefer to stay in ${ap.city}`;
    }
    return `You're in ${ap.city}, they're in ${bp.city} — neither has said they'd move`;
  }

  // 2. Timeframe
  const ta = TIMEFRAME_ORDER[a.answers?.timeframe];
  const tb = TIMEFRAME_ORDER[b.answers?.timeframe];
  if (ta != null && tb != null && ta !== tb) {
    return `You're seeking ${TIMEFRAME_LABEL[a.answers.timeframe]}; ` +
      `they're looking at ${TIMEFRAME_LABEL[b.answers.timeframe]}`;
  }

  // 3. Financial expectation
  const fa = ap.financialExpectation;
  const fb = bp.financialExpectation;
  if (fa && fb && fa !== fb) {
    return `You lean toward ${FINANCIAL_LABEL[fa] || fa}; ` +
      `they lean toward ${FINANCIAL_LABEL[fb] || fb}`;
  }

  // 4. Madhhab (both declared)
  if (ap.madhhab && bp.madhhab && ap.madhhab !== bp.madhhab) {
    return `Different madhhab — you follow ${ap.madhhab}, they follow ${bp.madhhab}`;
  }

  // 5. Family type
  if (ap.familyType && bp.familyType && ap.familyType !== bp.familyType) {
    return `You come from a ${ap.familyType} family, they from a ${bp.familyType} one`;
  }

  // Soft fallback — closely aligned, so name the thing worth exploring.
  return 'Very closely aligned — worth exploring your day-to-day deen goals in conversation';
}

function bandOf(score, cfg) {
  if (score >= cfg.bandStrong) return 'strong';
  if (score >= cfg.bandGood) return 'good';
  if (score >= cfg.bandSome) return 'some';
  return null; // below threshold → never shown
}

const BAND_RANK = { strong: 3, good: 2, some: 1 };

/**
 * Builds one user's daily batch.
 * @param user        seeker snapshot
 * @param candidates  pool snapshots
 * @param opts        { seen:Set, interestedInMe:Set, blocked:Set, limit,
 *                      now, cfg, exposure:Map<uid,count> }
 */
function buildBatch(user, candidates, opts = {}) {
  const seen = opts.seen || new Set();
  const interested = opts.interestedInMe || new Set();
  const blocked = opts.blocked || new Set();
  const limit = opts.limit || BATCH_LIMIT;
  const now = opts.now || new Date();
  const cfg = { ...DEFAULT_CFG, ...(opts.cfg || {}) };
  const exposure = opts.exposure || new Map();

  const eligible = candidates.filter(
    (c) =>
      c._id !== user._id &&
      !seen.has(c._id) &&
      !blocked.has(c._id) &&
      c.status === 'approved' &&
      c.profileComplete === true &&
      // Inactive >30 days drops out of circulation (pool hygiene, §4.2).
      !isStale(c, now) &&
      // Exposure cap — a profile can appear in at most N batches per day.
      (exposure.get(c._id) || 0) < cfg.exposureCapPerDay &&
      hardFilterPass(user, c, now)
  );

  const ranked = eligible
    .map((c) => {
      const { score, why, divergence } = scorePair(user, c, now);
      return {
        candidate: c,
        score,
        band: bandOf(score, cfg),
        why,
        divergence,
        interestedInMe: interested.has(c._id),
        recency: c.lastActiveAt ? new Date(c.lastActiveAt).getTime() : 0,
      };
    })
    // Below-threshold pairs are never shown (PRD §4.2).
    .filter((e) => e.band != null)
    // Rank: expressed-interest → band → recency → score → stable tiebreak.
    // Deliberately NOT raw score first (PRD §4.2).
    .sort(
      (x, y) =>
        Number(y.interestedInMe) - Number(x.interestedInMe) ||
        BAND_RANK[y.band] - BAND_RANK[x.band] ||
        y.recency - x.recency ||
        y.score - x.score ||
        x.candidate._id.localeCompare(y.candidate._id)
    );

  return ranked.slice(0, limit);
}

/** A profile inactive for >30 days is out of circulation (pool hygiene). */
function isStale(c, now = new Date()) {
  const last = c.lastActiveAt ? new Date(c.lastActiveAt) : null;
  if (!last) return false; // no signal → keep (new members have no activity)
  return now - last > 30 * 24 * 3600 * 1000;
}

/** IST calendar date string — batches are keyed by the Indian day. */
function istDateString(now = new Date()) {
  const ist = new Date(now.getTime() + 5.5 * 3600 * 1000);
  return ist.toISOString().slice(0, 10);
}

module.exports = {
  hardFilterPass,
  scorePair,
  buildBatch,
  bandOf,
  honestDivergence,
  istDateString,
  BATCH_LIMIT,
  DEFAULT_CFG,
};
