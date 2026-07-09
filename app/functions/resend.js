/**
 * Resend transactional email — the 6-digit sign-in code.
 * Node 22 ships a global fetch, so no HTTP dependency is needed.
 */

// Brand assets from the ikhlaas.io site (email clients block data: URIs,
// so they must be real https URLs). Hosted on our Firebase site from
// admin/web/. The wordmark is the header lockup; the mark is the round icon.
const WORDMARK_URL = 'https://ikhlas-admin.web.app/ikhlaas-wordmark.png';
const CONTACT_EMAIL = 'salaam@ikhlaas.io';

/** Branded HTML for the one-time code email. */
function otpEmailHtml(code) {
  const spaced = code.split('').join('&nbsp;&nbsp;');
  return `<!doctype html>
<html>
  <body style="margin:0;background:#EFF0E5;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EFF0E5;padding:40px 0;">
      <tr><td align="center">
        <table role="presentation" width="440" cellpadding="0" cellspacing="0"
               style="background:#ffffff;border:1px solid #DFE0D2;border-radius:14px;padding:40px 36px;">
          <tr><td align="center" style="padding-bottom:6px;">
            <img src="${WORDMARK_URL}" width="188" height="99" alt="Ikhlaas"
                 style="display:block;border:0;outline:none;text-decoration:none;" />
          </td></tr>
          <tr><td align="center" style="padding-top:22px;">
            <div style="font-size:15px;color:#4A554E;line-height:1.6;">
              Your sign-in code
            </div>
          </td></tr>
          <tr><td align="center" style="padding:18px 0 8px;">
            <div style="font-size:34px;font-weight:600;color:#17251B;letter-spacing:6px;">
              ${spaced}
            </div>
          </td></tr>
          <tr><td align="center" style="padding-top:14px;">
            <div style="font-size:13px;color:#7A857D;line-height:1.6;">
              Enter this code in the app to continue. It expires in 10&nbsp;minutes.
              If you didn't request it, you can safely ignore this email.
            </div>
          </td></tr>
          <tr><td align="center" style="padding-top:24px;">
            <div style="border-top:1px solid #EDEEE3;padding-top:16px;font-size:12px;color:#9AA396;line-height:1.7;">
              Need help? Write to us at
              <a href="mailto:${CONTACT_EMAIL}" style="color:#A8842B;text-decoration:none;">${CONTACT_EMAIL}</a>.
            </div>
          </td></tr>
        </table>
        <div style="font-size:11px;color:#9AA396;margin-top:18px;">
          Ikhlaas — nikah, the right way.
        </div>
      </td></tr>
    </table>
  </body>
</html>`;
}

/**
 * Sends the code via Resend. Throws on a non-2xx response so the caller
 * can surface a failure instead of silently "succeeding".
 * @param {string} apiKey  Resend API key.
 * @param {string} from    Verified sender, e.g. "Ikhlaas <noreply@ikhlaas.io>".
 * @param {string} to      Recipient email.
 * @param {string} code    6-digit code.
 */
async function sendOtpEmail(apiKey, from, to, code) {
  const text =
    `Your Ikhlaas sign-in code is ${code}.\n\n` +
    `Enter it in the app to continue. It expires in 10 minutes.\n` +
    `If you didn't request it, you can ignore this email.\n\n` +
    `Need help? Write to us at ${CONTACT_EMAIL}.\n` +
    `Ikhlaas — nikah, the right way.`;
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [to],
      reply_to: CONTACT_EMAIL,
      subject: `${code} is your Ikhlaas sign-in code`,
      html: otpEmailHtml(code),
      text,
    }),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`Resend ${res.status}: ${detail.slice(0, 300)}`);
  }
  return res.json().catch(() => ({}));
}

module.exports = { sendOtpEmail, otpEmailHtml };
