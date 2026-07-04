const { test } = require('node:test');
const assert = require('node:assert');
const { evaluateGate } = require('./gate');

const GOOD_ANSWERS = {
  timeframe: '6_12m',
  prayer: 'five_daily',
  financiallyReady: 'ready',
  familyAware: 'yes',
  e1_tawhid: 'affirm',
  e2_riba: 'affirm',
  e3_ribaPractice: 'none',
  shortAnswers: {
    whyNow: 'x'.repeat(160),
    deenRelationship: 'y'.repeat(160),
  },
};

const SELFIE = { hasSelfie: true };
const ADULT = new Date(new Date().getFullYear() - 25, 0, 1);
const MINOR = new Date(new Date().getFullYear() - 16, 0, 1);

test('clean application auto-passes', () => {
  const v = evaluateGate(GOOD_ANSWERS, ADULT, {}, SELFIE);
  assert.equal(v.result, 'auto_pass');
});

test('under-18 hard-blocks regardless of answers', () => {
  const v = evaluateGate(GOOD_ANSWERS, MINOR, {}, SELFIE);
  assert.equal(v.result, 'auto_reject');
  assert.deepEqual(v.reasons, ['under_min_age']);
});

test('missing dob never auto-passes', () => {
  const v = evaluateGate(GOOD_ANSWERS, null, {}, SELFIE);
  assert.equal(v.result, 'auto_reject');
});

test('"exploring" timeframe soft-rejects (the gate doing its job)', () => {
  const v = evaluateGate({ ...GOOD_ANSWERS, timeframe: 'exploring' }, ADULT, {}, SELFIE);
  assert.equal(v.result, 'auto_reject');
  assert.ok(v.reasons.some((r) => r.includes('timeframe')));
});

test('prayer working/rarely soft-rejects; five_daily passes', () => {
  for (const p of ['working', 'rarely']) {
    assert.equal(
      evaluateGate({ ...GOOD_ANSWERS, prayer: p }, ADULT, {}, SELFIE).result,
      'auto_reject'
    );
  }
});

test('prayer "most" routes to manual review (Ab\'s ruling, July 2026)', () => {
  const v = evaluateGate({ ...GOOD_ANSWERS, prayer: 'most' }, ADULT, {}, SELFIE);
  assert.equal(v.result, 'manual_review');
});

test('E1/E2 not_affirm and E3 continuing soft-reject', () => {
  assert.equal(
    evaluateGate({ ...GOOD_ANSWERS, e1_tawhid: 'not_affirm' }, ADULT, {}, SELFIE).result,
    'auto_reject'
  );
  assert.equal(
    evaluateGate({ ...GOOD_ANSWERS, e2_riba: 'not_affirm' }, ADULT, {}, SELFIE).result,
    'auto_reject'
  );
  assert.equal(
    evaluateGate({ ...GOOD_ANSWERS, e3_ribaPractice: 'continuing' }, ADULT, {}, SELFIE)
      .result,
    'auto_reject'
  );
});

test('E3 exiting still passes (honest-disclosure badge case)', () => {
  const v = evaluateGate({ ...GOOD_ANSWERS, e3_ribaPractice: 'exiting' }, ADULT, {}, SELFIE);
  assert.equal(v.result, 'auto_pass');
});

test('short answers below minimum escalate to a human, never auto-decide', () => {
  const v = evaluateGate(
    { ...GOOD_ANSWERS, shortAnswers: { whyNow: 'short', deenRelationship: 'short' } },
    ADULT, {}, SELFIE
  );
  assert.equal(v.result, 'manual_review');
});

test('missing structured answers escalate, never auto-pass', () => {
  const { e1_tawhid, ...withoutE1 } = GOOD_ANSWERS;
  const v = evaluateGate(withoutE1, ADULT, {}, SELFIE);
  assert.equal(v.result, 'manual_review');
});

test('reject beats manual-review when both trigger', () => {
  const v = evaluateGate(
    { ...GOOD_ANSWERS, prayer: 'most', e2_riba: 'not_affirm' },
    ADULT, {}, SELFIE
  );
  assert.equal(v.result, 'auto_reject');
});

test('config rules override defaults', () => {
  // Tightened rule: "most" becomes an auto-reject.
  const v = evaluateGate({ ...GOOD_ANSWERS, prayer: 'most' }, ADULT, {
    autoRejectAnswers: { prayer: ['most', 'working', 'rarely'] },
  }, SELFIE);
  assert.equal(v.result, 'auto_reject');
});

test('missing selfie escalates to manual review, never auto-passes', () => {
  const v = evaluateGate(GOOD_ANSWERS, ADULT, {}, { hasSelfie: false });
  assert.equal(v.result, 'manual_review');
  assert.ok(v.reasons.includes('manual_review:missing:selfie'));
});

test('missing selfie does not soften a clear reject', () => {
  const v = evaluateGate(
    { ...GOOD_ANSWERS, e1_tawhid: 'not_affirm' },
    ADULT, {}, { hasSelfie: false }
  );
  assert.equal(v.result, 'auto_reject');
});
