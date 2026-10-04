/**
 * Delete every SHA certificate fingerprint on the Firebase Android app, then
 * re-add them.
 *
 * Why this exists: a fingerprint added while another project still held the
 * same (package name + SHA-1) pair is stored by Firebase, but Google refuses
 * to create the Android OAuth client behind it — and nothing ever retries.
 * The app then looks correctly configured while Google Sign-In fails with
 * DEVELOPER_ERROR, because the OAuth client it needs does not exist. The only
 * way to trigger creation is to remove the fingerprint and add it back once
 * the pair is free.
 *
 * Doing it through the Management API rather than the console because the
 * console's delete-and-re-add silently did not produce the client.
 *
 * Verify afterwards at:
 *   https://console.cloud.google.com/apis/credentials?project=<project>
 * An "Android client for io.ikhlaas.app" row must appear under OAuth 2.0
 * Client IDs. Its absence is the actual fault; the console's conflict banner
 * is only advisory.
 *
 * Run:  node scripts/resha.js
 */
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const gsPath = path.join(__dirname, '..', '..', 'android', 'app', 'google-services.json');
  const gs = JSON.parse(fs.readFileSync(gsPath, 'utf8'));
  const project = gs.project_info.project_id;
  const pkg = 'io.ikhlaas.app';
  const appId = gs.client.find(
    (c) => c.client_info?.android_client_info?.package_name === pkg,
  )?.client_info?.mobilesdk_app_id;
  if (!appId) throw new Error(`no android app for ${pkg} in google-services.json`);

  const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
  const client = await auth.getClient();
  const base = `https://firebase.googleapis.com/v1beta1/projects/${project}/androidApps/${appId}/sha`;

  console.log(`project ${project}, app ${appId}`);

  const list = await client.request({ url: base, method: 'GET' });
  const certs = list.data.certificates || [];
  if (!certs.length) {
    console.log('no fingerprints registered — nothing to cycle');
    return;
  }
  console.log(`found ${certs.length} fingerprint(s)`);

  // Keep hash + type before deleting; `name` is the resource path to DELETE.
  const saved = certs.map((c) => ({
    name: c.name,
    shaHash: c.shaHash,
    certType: c.certType,
  }));

  for (const c of saved) {
    await client.request({
      url: `https://firebase.googleapis.com/v1beta1/${c.name}`,
      method: 'DELETE',
    });
    console.log(`  deleted ${c.certType} ${c.shaHash}`);
  }

  // Let the deletion settle before re-adding; creating the OAuth client is a
  // side effect of the add, and racing it is how we end up here again.
  await sleep(5000);

  for (const c of saved) {
    await client.request({
      url: base,
      method: 'POST',
      data: { shaHash: c.shaHash, certType: c.certType },
    });
    console.log(`  re-added ${c.certType} ${c.shaHash}`);
  }

  console.log('done — now check that an Android OAuth client exists at:');
  console.log(`  https://console.cloud.google.com/apis/credentials?project=${project}`);
}

main().catch((e) => {
  console.error(e.response?.data?.error?.message || e.message || e);
  process.exit(1);
});
