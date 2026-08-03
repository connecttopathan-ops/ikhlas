/**
 * WhatsApp delivery via the Meta (WhatsApp Cloud) API. Node 22 ships a global
 * fetch, so no HTTP dependency is needed.
 *
 * A guardian digest is a BUSINESS-INITIATED message (the guardian never
 * messaged us first, and it lands outside any 24-hour service window), so
 * Meta requires a PRE-APPROVED message template. Template variables cannot
 * contain newlines or multi-line text, so the raw transcript never rides in
 * the WhatsApp message — it stays in waliDigests/* for the wali portal. The
 * template carries a notification: ward name + new-message count.
 *
 * Provisioning (one-time, outside this repo):
 *   1. WhatsApp Business Account + verified Meta Business.
 *   2. A phone number → its PHONE_NUMBER_ID.
 *   3. A permanent access token → secret WHATSAPP_TOKEN.
 *   4. An approved template (default name `wali_digest`) whose BODY has two
 *      variables, e.g.:
 *        "As-salamu alaykum {{1}}. There is new activity in the Ikhlaas
 *         conversation you oversee — {{2}} new message(s). Please review it
 *         together, insha’Allah."
 *   5. config/whatsapp = { phoneNumberId, templateName?, languageCode? }.
 */

const GRAPH_VERSION = 'v21.0';

/** Meta wants the number as country-code + digits, no '+' and no separators. */
function toWaNumber(phone) {
  return String(phone || '').replace(/[^\d]/g, '');
}

/**
 * Sends the guardian digest notification template. Throws on a non-2xx so the
 * caller can record delivery truthfully instead of silently "succeeding".
 * @param {object} o
 * @param {string} o.token          Permanent access token (WHATSAPP_TOKEN).
 * @param {string} o.phoneNumberId  Sender phone number id.
 * @param {string} o.templateName   Approved template name.
 * @param {string} o.languageCode   Template language, e.g. 'en'.
 * @param {string} o.toPhone        Guardian phone (any format; normalised).
 * @param {string} o.wardName       Ward's display name → {{1}}.
 * @param {number} o.messageCount   New-message count → {{2}}.
 * @returns {Promise<object>} Meta's response body (contains the message id).
 */
async function sendWaliDigestWhatsApp(o) {
  const url =
    `https://graph.facebook.com/${GRAPH_VERSION}/${o.phoneNumberId}/messages`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${o.token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: toWaNumber(o.toPhone),
      type: 'template',
      template: {
        name: o.templateName || 'wali_digest',
        language: { code: o.languageCode || 'en' },
        components: [
          {
            type: 'body',
            parameters: [
              { type: 'text', text: String(o.wardName || 'their ward') },
              { type: 'text', text: String(o.messageCount) },
            ],
          },
        ],
      },
    }),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`WhatsApp ${res.status}: ${detail.slice(0, 300)}`);
  }
  return res.json().catch(() => ({}));
}

module.exports = { sendWaliDigestWhatsApp, toWaNumber };
