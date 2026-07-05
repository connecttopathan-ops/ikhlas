/**
 * Matching engine v1 — deterministic, no ML (PRD §4.2).
 * Pure functions: user snapshots in, ranked batch out. No I/O.
 *
 * Model: curated daily batch of at most 5, NOT swiping.
 *   1. Hard filters first, MUTUAL (both directions must accept)
 *   2. Scoring — deen-practice alignment weighted heaviest
 *   3. Freshness/fairness boosts; expressed-interest-in-me surfaces first
 */

const BATCH_LIMIT = 5;

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
  return true;
}

/** Mutual hard filters (PRD: both users' filters respected bidirectionally). */
function hardFilterPass(a, b, now = new Date()) {
  if (!a.gender || !b.gender || a.gender === b.gender) return false;
  return accepts(a, b, now) && accepts(b, a, now);
}

const TIMEFRAME_ORDER = { '6m': 0, '6_12m': 1, '12_24m': 2 };

/**
 * Deterministic score. Deen alignment heaviest (PRD §4.2 scoring #2).
 * `answersA`/`answersB` are the application answers (prayer, timeframe).
 */
function scorePair(a, b, now = new Date()) {
  let score = 0;
  const why = [];

  // Deen practice — heaviest weight
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

  // Timeframe alignment
  const ta = TIMEFRAME_ORDER[a.answers?.timeframe];
  const tb = TIMEFRAME_ORDER[b.answers?.timeframe];
  if (ta != null && tb != null) {
    const d = Math.abs(ta - tb);
    score += d === 0 ? 20 : d === 1 ? 12 : 5;
    if (d === 0) why.push('Same nikah timeframe');
  }

  // Shared language
  const la = new Set(a.profile?.languages || []);
  const shared = (b.profile?.languages || []).filter((l) => la.has(l));
  if (shared.length > 0) {
    score += 15;
    why.push(`You both speak ${shared[0]}`);
  }

  // Geography
  if (a.profile?.city && a.profile.city === b.profile?.city) {
    score += 10;
    why.push(`Both in ${a.profile.city}`);
  } else if (a.profile?.country && a.profile.country === b.profile?.country) {
    score += 5;
  }

  // Madhhab affinity (optional fields — only when both declared)
  if (a.profile?.madhhab && a.profile.madhhab === b.profile?.madhhab) {
    score += 10;
    why.push('Same madhhab');
  }

  // Relocation openness pairs well
  if (a.profile?.willingToRelocate && b.profile?.willingToRelocate) {
    score += 5;
    why.push('Both open to relocating');
  }

  // Freshness/fairness: recently active candidates boosted
  const last = b.lastActiveAt ? new Date(b.lastActiveAt) : null;
  if (last && now - last < 7 * 24 * 3600 * 1000) score += 10;

  return { score, why: why.slice(0, 3) };
}

/**
 * Builds one user's daily batch.
 * @param user        seeker snapshot ({_id, gender, dob, profile, preferences, answers, lastActiveAt})
 * @param candidates  pool snapshots (same shape)
 * @param opts        { seen: Set<uid>, interestedInMe: Set<uid>, limit }
 */
function buildBatch(user, candidates, opts = {}) {
  const seen = opts.seen || new Set();
  const interested = opts.interestedInMe || new Set();
  const limit = opts.limit || BATCH_LIMIT;
  const now = opts.now || new Date();

  const blocked = opts.blocked || new Set();
  const eligible = candidates.filter(
    (c) =>
      c._id !== user._id &&
      !seen.has(c._id) &&
      !blocked.has(c._id) &&
      c.status === 'approved' &&
      c.profileComplete === true &&
      hardFilterPass(user, c, now)
  );

  const ranked = eligible
    .map((c) => {
      const { score, why } = scorePair(user, c, now);
      return {
        candidate: c,
        score: score + (interested.has(c._id) ? 25 : 0),
        why,
        interestedInMe: interested.has(c._id),
      };
    })
    .sort(
      (x, y) =>
        Number(y.interestedInMe) - Number(x.interestedInMe) ||
        y.score - x.score ||
        x.candidate._id.localeCompare(y.candidate._id) // deterministic tiebreak
    );

  return ranked.slice(0, limit);
}

/** IST calendar date string — batches are keyed by the Indian day. */
function istDateString(now = new Date()) {
  const ist = new Date(now.getTime() + 5.5 * 3600 * 1000);
  return ist.toISOString().slice(0, 10);
}

module.exports = { hardFilterPass, scorePair, buildBatch, istDateString, BATCH_LIMIT };
