'use strict';

// B45 P11. APNs transport ONLY. No automatic scheduling, no iPhone token
// registration, and no background work until the official generator is wired.
// Signing keys are read from server environment only: never put them in Flutter.
const crypto = require('node:crypto');
const http2 = require('node:http2');

const DEVICE_TOKEN = /^[a-fA-F0-9]{64}$/;
const DAY_KEY = /^\d{4}-\d{2}-\d{2}$/;
const APP_ID = /^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;
const ID = /^[A-Za-z0-9]{10}$/;
const ORIGINS = Object.freeze({
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
});

function base64url(source) {
  return Buffer.from(source).toString('base64url');
}

function createProviderToken({keyId, teamId, privateKey, issuedAt}) {
  if (!ID.test(keyId || '') || !ID.test(teamId || '') ||
      !Number.isSafeInteger(issuedAt) || issuedAt < 0) {
    throw new Error('APNs configuration invalid');
  }
  const signingKey = crypto.createPrivateKey(privateKey);
  if (signingKey.asymmetricKeyType !== 'ec' ||
      signingKey.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('APNs P-256 key required');
  }
  const content = `${base64url(JSON.stringify({alg: 'ES256', kid: keyId}))}.` +
    base64url(JSON.stringify({iss: teamId, iat: issuedAt}));
  const signature = crypto.sign('sha256', Buffer.from(content), {
    key: signingKey, dsaEncoding: 'ieee-p1363',
  });
  return `${content}.${base64url(signature)}`;
}

function couponReadyPayload({dayKey, coupon}) {
  if (!DAY_KEY.test(dayKey || '') ||
      !(coupon && Array.isArray(coupon.events) &&
        coupon.events.length >= 3 && coupon.events.length <= 6)) {
    throw new Error('No validated daily coupon');
  }
  // Never put individual bets, user identity or tokens into push notifications.
  return JSON.stringify({
    aps: {alert: {title: 'GoalVdLine',
      body: `La tua schedina di oggi è pronta: ${coupon.events.length} eventi.`},
    sound: 'default'},
    kind: 'auto_coupon_ready', dayKey,
  });
}

function apnsReady({env = process.env} = {}) {
  if (env.AUTO_COUPON_PUSH_ENABLED !== 'true' ||
      env.AUTO_COUPON_WORKER_ENABLED !== 'true' ||
      !ID.test(env.APNS_KEY_ID || '') || !ID.test(env.APNS_TEAM_ID || '') ||
      !APP_ID.test(env.APNS_BUNDLE_ID || '') ||
      typeof env.APNS_PRIVATE_KEY_BASE64 !== 'string' ||
      !['production', 'sandbox'].includes(env.APNS_ENVIRONMENT)) return false;
  try {
    const keyPem = Buffer.from(env.APNS_PRIVATE_KEY_BASE64, 'base64').toString('utf8');
    const key = crypto.createPrivateKey(keyPem);
    return key.asymmetricKeyType === 'ec' &&
      key.asymmetricKeyDetails?.namedCurve === 'prime256v1';
  } catch (_) {
    return false;
  }
}

function requestApns({origin, headers, payload, connect = http2.connect, timeoutMs = 8000}) {
  return new Promise((resolve, reject) => {
    let client;
    let request;
    let settled = false;
    let status = null;
    let responseBytes = 0;
    const finish = (err, value) => {
      if (settled) return;
      settled = true;
      if (request) request.close();
      if (client) client.close();
      if (err) reject(err); else resolve(value);
    };
    try {
      client = connect(origin);
      client.on('error', () => finish(new Error('APNs transport failure')));
      request = client.request(headers);
      request.setTimeout(timeoutMs, () => finish(new Error('APNs timeout')));
      request.on('response', h => { status = Number(h[':status']); });
      request.on('data', chunk => { responseBytes += Buffer.byteLength(chunk); });
      request.on('end', () => finish(null, {status, responseBytes}));
      request.on('error', () => finish(new Error('APNs transport failure')));
      request.end(payload);
    } catch (_) {
      finish(new Error('APNs transport failure'));
    }
  });
}

async function sendAutoCouponReadyPush({env = process.env, deviceToken, dayKey, coupon,
  now = () => new Date(), transport = requestApns} = {}) {
  // Explicitly off by default and independent of the worker authentication token.
  if (!apnsReady({env})) return {status: 'disabled'};
  if (!DEVICE_TOKEN.test(deviceToken || '')) return {status: 'invalid_device_token'};
  let payload;
  try { payload = couponReadyPayload({dayKey, coupon}); }
  catch (_) { return {status: 'invalid_coupon'}; }
  const timestamp = now();
  if (!(timestamp instanceof Date) || !Number.isFinite(timestamp.getTime())) {
    return {status: 'invalid_clock'};
  }
  try {
    const jwt = createProviderToken({
      keyId: env.APNS_KEY_ID,
      teamId: env.APNS_TEAM_ID,
      privateKey: Buffer.from(env.APNS_PRIVATE_KEY_BASE64, 'base64').toString('utf8'),
      issuedAt: Math.floor(timestamp.getTime() / 1000),
    });
    const result = await transport({
      origin: ORIGINS[env.APNS_ENVIRONMENT],
      headers: {
        ':method': 'POST',
        ':path': `/3/device/${deviceToken.toLowerCase()}`,
        'authorization': `bearer ${jwt}`,
        'apns-topic': env.APNS_BUNDLE_ID,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-collapse-id': `auto-${dayKey}`,
        'apns-expiration': '0',
        'content-type': 'application/json',
      }, payload,
    });
    // 200 means Apple accepted the request, NOT guaranteed delivery on device.
    if (result.status === 200) return {status: 'accepted_by_apns'};
    if (result.status === 410) return {status: 'unregistered_device'};
    return {status: 'rejected_by_apns', httpStatus: result.status};
  } catch (_) {
    // Key and network errors must not leak to API clients or logs.
    return {status: 'transport_error'};
  }
}

module.exports = {
  apnsReady, couponReadyPayload, createProviderToken,
  requestApns, sendAutoCouponReadyPush,
};
