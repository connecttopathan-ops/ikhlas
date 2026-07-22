// ID-document verification helpers (closed-testing tier).
//
// IMPORTANT: OCR extracts text; a HUMAN decides authenticity. Nothing here
// returns an "authentic/fake" verdict — only a name-match signal, a last-4,
// and whether a face is present. Every field is decision *support* for the
// admin's manual review (PRD Step 4A). Phase 2 swaps this for DigiLocker/
// Aadhaar-OTP + passport MRZ + a real face-match provider (HyperVerge/Rekognition).

let _vision = null;
function visionClient() {
  if (_vision === null) {
    try {
      // Lazy require so a Vision outage/missing dep can't break module load.
      const { ImageAnnotatorClient } = require('@google-cloud/vision');
      _vision = new ImageAnnotatorClient();
    } catch (e) {
      _vision = false;
    }
  }
  return _vision || null;
}

/** Full text of an ID image via Cloud Vision. Returns '' on any failure. */
async function ocrText(buffer) {
  const client = visionClient();
  if (!client) return '';
  try {
    const [res] = await client.documentTextDetection({ image: { content: buffer } });
    return res?.fullTextAnnotation?.text || '';
  } catch (e) {
    console.error('vision OCR failed', e?.message);
    return '';
  }
}

/** True if Vision detects at least one face in the image. Null on failure. */
async function hasFace(buffer) {
  const client = visionClient();
  if (!client) return null;
  try {
    const [res] = await client.faceDetection({ image: { content: buffer } });
    return (res?.faceAnnotations?.length || 0) > 0;
  } catch (e) {
    console.error('vision face detection failed', e?.message);
    return null;
  }
}

const norm = (s) =>
  String(s || '')
    .toUpperCase()
    .replace(/[^A-Z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

/**
 * How well the application name appears in the document's OCR text (0..1) —
 * the fraction of the applicant's name tokens (>=2 chars) found in the text.
 * A robust, auditable signal that avoids guessing which OCR line "is" the name.
 */
function nameMatchScore(applicationName, text) {
  const nameTokens = norm(applicationName).split(' ').filter((t) => t.length >= 2);
  if (nameTokens.length === 0 || !text) return 0;
  const hay = norm(text);
  const hit = nameTokens.filter((t) => hay.includes(t)).length;
  return Math.round((hit / nameTokens.length) * 100) / 100;
}

/** Best-effort candidate name line for the admin's eye (never authoritative). */
function candidateName(text, type) {
  const lines = String(text || '').split('\n').map((l) => l.trim()).filter(Boolean);
  if (type === 'passport') {
    // MRZ surname<<given — pull the P< line if present.
    const mrz = lines.find((l) => /^P[<A-Z0-9]/.test(l.replace(/\s/g, '')));
    if (mrz) {
      const body = mrz.replace(/\s/g, '').slice(5); // after P<XXX
      return body.replace(/</g, ' ').replace(/\s+/g, ' ').trim() || null;
    }
  }
  // Fallback: the longest mostly-alpha line.
  const alpha = lines
    .filter((l) => /^[A-Za-z .]+$/.test(l) && l.length >= 4)
    .sort((a, b) => b.length - a.length);
  return alpha[0] || null;
}

/**
 * Last 4 digits of the ID number — NEVER the full number (Aadhaar-Act safe).
 * Aadhaar: a 12-digit run. Passport: the alphanumeric doc number's last 4.
 */
function last4Of(text, type) {
  const flat = String(text || '');
  if (type === 'aadhaar') {
    const m = flat.replace(/\s/g, '').match(/(\d{12})(?!\d)/);
    if (m) return m[1].slice(-4);
    const any = flat.replace(/\D/g, '');
    return any.length >= 4 ? any.slice(-4) : null;
  }
  // passport: letter + 7-8 digits, or MRZ number field.
  const m = flat.replace(/\s/g, '').match(/([A-Z][0-9]{6,8})/);
  if (m) return m[1].slice(-4);
  const digits = flat.replace(/\D/g, '');
  return digits.length >= 4 ? digits.slice(-4) : null;
}

/**
 * Run the full support-signal extraction on an ID image. Pure-ish (I/O only to
 * Vision); returns everything the admin needs plus a null faceMatchScore —
 * the identity match is the admin's visual call this tier, never automated.
 */
async function analyzeIdDoc({ idBuffer, selfieBuffer, applicationName, type }) {
  const [text, idFace, selfieFace] = await Promise.all([
    ocrText(idBuffer),
    hasFace(idBuffer),
    selfieBuffer ? hasFace(selfieBuffer) : Promise.resolve(null),
  ]);
  return {
    ocrName: candidateName(text, type),
    nameMatchScore: nameMatchScore(applicationName, text),
    last4: last4Of(text, type),
    // No automated identity comparison this tier — human compares the images.
    faceMatchScore: null,
    faceMatchMethod: 'manual',
    idFacePresent: idFace,
    selfieFacePresent: selfieFace,
  };
}

module.exports = {
  analyzeIdDoc,
  nameMatchScore,
  candidateName,
  last4Of,
};
