// Read-only preflight: distinguish invalid API credentials from an inaccessible app.
// Never print the private key, signed token or raw Apple response.
import { createPrivateKey, sign } from 'node:crypto';

export async function checkAccess(env = process.env, request = fetch) {
  const keyId = env.APP_STORE_KEY_ID?.trim();
  const issuer = env.APP_STORE_ISSUER_ID?.trim();
  const pem = env.API_KEY_P8?.trim();
  if (!keyId || !issuer || !pem) throw new Error('App Store Connect API credential is incomplete.');
  let key;
  try {
    key = createPrivateKey(pem);
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails.namedCurve !== 'prime256v1') throw new Error();
  } catch {
    throw new Error('APP_STORE_CONNECT_API_KEY_P8 is not a valid ES256 private key.');
  }
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const body = `${encode({ alg: 'ES256', kid: keyId, typ: 'JWT' })}.${encode({ iss: issuer, iat: now, exp: now + 300, aud: 'appstoreconnect-v1' })}`;
  const signature = sign('sha256', Buffer.from(body), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  let response;
  try {
    response = await request('https://api.appstoreconnect.apple.com/v1/apps/6792147141?fields%5Bapps%5D=bundleId', {
      headers: { Authorization: `Bearer ${body}.${signature}` }, signal: AbortSignal.timeout(30000),
    });
  } catch {
    throw new Error('App Store Connect API request failed or timed out.');
  }
  if (!response.ok) {
    // Apple's error code/title explains account-level blocks such as agreements.
    // Only emit these bounded fields; never dump the response or request headers.
    try {
      const failure = await response.json();
      for (const item of (failure.errors ?? []).slice(0, 3)) {
        const safe = value => String(value ?? '').replace(/[\r\n\x00-\x1f]/g, ' ').slice(0, 400);
        console.error(`Apple API error: ${safe(item.code)} | ${safe(item.title)} | ${safe(item.detail)}`);
      }
    } catch { /* The HTTP status below remains sufficient if there is no JSON. */ }
  }
  if (response.status === 401) throw new Error('Apple rejected API authentication (HTTP 401). Verify the Key ID, Issuer ID and matching .p8 private key together.');
  if (response.status === 403) throw new Error('Apple denied access to Balm (HTTP 403). Check the API key team, permissions and account agreements.');
  if (response.status === 404) throw new Error('Balm app 6792147141 is not visible to this API credential (HTTP 404). Check the Apple team.');
  if (!response.ok) throw new Error(`App Store Connect returned HTTP ${response.status}.`);
  let result;
  try { result = await response.json(); } catch { throw new Error('Apple returned an invalid API response.'); }
  if (result.data?.id !== '6792147141' || result.data?.attributes?.bundleId !== 'app.balm') throw new Error('Apple app record does not match the expected Balm bundle ID.');
  return 'API authentication passed; Balm app 6792147141 / app.balm is accessible.';
}

if (process.argv[1]?.endsWith('/check-app-store-access.mjs')) {
  try { console.log(await checkAccess()); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
