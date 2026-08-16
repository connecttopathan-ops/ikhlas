/**
 * Register SHA certificate fingerprints on the Firebase Android app via the
 * Firebase Management API, so Google Sign-In authorizes builds signed with
 * that key (e.g. Play App Signing's key). Uses the deploy service account's
 * credentials (GOOGLE_APPLICATION_CREDENTIALS).
 *
 * Env: SHA1, SHA256 (either or both; colon-separated or plain hex).
 * Reads the Android appId + project from ../android/app/google-services.json.
 *
 * Run:  SHA1=.. SHA256=.. node scripts/add-sha.js
 */
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const norm = (s) => String(s || '').replace(/:/g, '').trim().toLowerCase();

async function main() {
  const gsPath = path.join(__dirname, '..', '..', 'android', 'app', 'google-services.json');
  const gs = JSON.parse(fs.readFileSync(gsPath, 'utf8'));
  const project = gs.project_info.project_id;
  const pkg = 'io.ikhlaas.app';
  let appId;
  for (const c of gs.client) {
    if (c.client_info?.android_client_info?.package_name === pkg) {
      appId = c.client_info.mobilesdk_app_id;
      break;
    }
  }
  if (!appId) throw new Error(`no android app for ${pkg} in google-services.json`);

  const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
  const client = await auth.getClient();
  const base = `https://firebase.googleapis.com/v1beta1/projects/${project}/androidApps/${appId}/sha`;

  // Existing fingerprints (avoid noisy duplicates).
  let existing = new Set();
  try {
    const list = await client.request({ url: base, method: 'GET' });
    for (const c of list.data.certificates || []) existing.add(norm(c.shaHash));
  } catch (e) {
    console.log('list existing failed (continuing):', e.response?.status || e.message);
  }

  async function add(hash, type) {
    const h = norm(hash);
    if (!h) return;
    if (existing.has(h)) { console.log(`${type} already registered — skipping`); return; }
    try {
      await client.request({ url: base, method: 'POST', data: { shaHash: h, certType: type } });
      console.log(`registered ${type}: ${h}`);
    } catch (e) {
      const msg = e.response?.data?.error?.message || e.message;
      const code = e.response?.status;
      if (code === 409 || /already exists/i.test(msg)) console.log(`${type} already exists — ok`);
      else throw new Error(`${type} failed (${code}): ${msg}`);
    }
  }

  console.log(`project ${project}, app ${appId}`);
  await add(process.env.SHA1, 'SHA_1');
  await add(process.env.SHA256, 'SHA_256');
  console.log('sha registration complete');
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
