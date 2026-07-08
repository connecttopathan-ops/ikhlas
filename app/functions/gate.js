/**
 * Deterministic gate engine — Tier 1 of the three-tier review funnel
 * (ikhlas-tech-requirements.md §3). Pure function: answers + dob + rules
 * in, verdict out. No I/O here so it unit-tests without emulators.
 *
 * Results:
 *   auto_reject    — clear reject (creed/timeframe/prayer/age rules)
 *   manual_review  — ambiguous middle → human queue (AI triage joins in W3)
 *   auto_pass      — clear pass
 *
 * NOTE: AI (Week 3) may auto-approve and auto-reject junk, but NEVER
 * auto-rejects on faith-sincerity — that always escalates to a human.
 * This tier only rejects on explicit structured answers, never prose.
 */

const DEFAULT_RULES = {
  minAge: 18,
  shortAnswerMinChars: 100,
  autoRejectAnswers: {
    timeframe: ['exploring'],
    prayer: ['working', 'rarely'],
    e1_tawhid: ['not_affirm'],
    e2_riba: ['not_affirm'],
    e3_ribaPractice: ['continuing'],
  },
  manualReviewAnswers: {
    prayer: ['most'],
  },
};

/**
 * @param {object} answers   applications/{uid}.answers
 * @param {Date|null} dob    users/{uid}.dob as JS Date
 * @param {object} rules     config/gateRules doc (merged over defaults)
 * @param {object} ctx       { hasSelfie } — verification context
 * @returns {{result: 'auto_pass'|'auto_reject'|'manual_review', reasons: string[]}}
 */
function evaluateGate(answers, dob, rules = {}, ctx = {}) {
  const r = {
    ...DEFAULT_RULES,
    ...rules,
    autoRejectAnswers: {
      ...DEFAULT_RULES.autoRejectAnswers,
      ...(rules.autoRejectAnswers || {}),
    },
    manualReviewAnswers: {
      ...DEFAULT_RULES.manualReviewAnswers,
      ...(rules.manualReviewAnswers || {}),
    },
  };
  const reasons = [];

  // Age — under-18 hard-blocks, no retry loophole (PRD §4.1 acceptance).
  if (!dob || ageInYears(dob) < r.minAge) {
    return { result: 'auto_reject', reasons: ['under_min_age'] };
  }

  // Structured auto-reject rules (creed E1–E3, timeframe, prayer).
  for (const [field, rejected] of Object.entries(r.autoRejectAnswers)) {
    if (rejected.includes(answers?.[field])) {
      reasons.push(`auto_reject:${field}=${answers[field]}`);
    }
  }
  if (reasons.length > 0) return { result: 'auto_reject', reasons };

  // Manual-review triggers ("most" prayers routes to a human — Ab's ruling).
  for (const [field, flagged] of Object.entries(r.manualReviewAnswers)) {
    if (flagged.includes(answers?.[field])) {
      reasons.push(`manual_review:${field}=${answers[field]}`);
    }
  }

  // Short answers below minimum → a human looks (client enforces the
  // minimum, so hitting this means someone bypassed the app).
  const sa = answers?.shortAnswers || {};
  for (const key of ['whyNow', 'deenRelationship']) {
    if (((sa[key] || '').trim()).length < r.shortAnswerMinChars) {
      reasons.push(`manual_review:short_answer:${key}`);
    }
  }

  // Required structured answers missing entirely → human, never auto-pass.
  for (const field of ['timeframe', 'prayer', 'e1_tawhid', 'e2_riba', 'e3_ribaPractice']) {
    if (!answers?.[field]) reasons.push(`manual_review:missing:${field}`);
  }

  // Selfie is mandatory before any approval (PRD §4.1 Step 4). With
  // manual capture there is no liveness verdict, so absence escalates
  // to a human rather than auto-approving an unverified applicant.
  if (!ctx.hasSelfie) reasons.push('manual_review:missing:selfie');

  if (reasons.length > 0) return { result: 'manual_review', reasons };
  return { result: 'auto_pass', reasons: ['all_deterministic_rules_passed'] };
}

function ageInYears(dob) {
  const now = new Date();
  let age = now.getFullYear() - dob.getFullYear();
  const beforeBirthday =
    now.getMonth() < dob.getMonth() ||
    (now.getMonth() === dob.getMonth() && now.getDate() < dob.getDate());
  if (beforeBirthday) age--;
  return age;
}

module.exports = { evaluateGate, DEFAULT_RULES };
