'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {EventEmitter} = require('node:events');
const {
  apnsReady, couponReadyPayload, createProviderToken,
  requestApns, sendAutoCouponReadyPush,
} = require('../auto_coupon/apns_provider');

const {privateKey, publicKey} = crypto.generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const key = privateKey.export({format: 'pem', type: 'pkcs8'}).toString();
const env = {
  AUTO_COUPON_PUSH_ENABLED: 'true', AUTO_COUPON_WORKER_ENABLED: 'true',
  APNS_KEY_ID: 'ABCDEFGHIJ', APNS_TEAM_ID: 'KLMNOPQRST',
  APNS_BUNDLE_ID: 'com.example.goalvdline', APNS_ENVIRONMENT: 'sandbox',
  APNS_PRIVATE_KEY_BASE64: Buffer.from(key).toString('base64'),
};
const deviceToken = 'abcd'.repeat(16);
const coupon = {events: Array.from({length: 4}, (_, i) => ({fixtureId: i + 1}))};

function send(overrides = {}) {
  return sendAutoCouponReadyPush({env, deviceToken, dayKey: '2026-11-09', coupon,
    now: () => new Date('2026-11-09T08:00:00Z'), ...overrides});
}

test('APNs is strictly disabled by default, and requires worker + valid signing key', async () => {
  assert.equal(apnsReady({env: {}}), false);
  assert.equal((await send({env: {}})).status, 'disabled');
  assert.equal(apnsReady({env: {...env, AUTO_COUPON_WORKER_ENABLED: 'false'}}), false);
  assert.equal(apnsReady({env: {...env, APNS_PRIVATE_KEY_BASE64: 'not a key'}}), false);
  assert.equal(apnsReady({env}), true);
});

test('ES256 provider token includes valid Apple claims and P-256 signature', () => {
  const jwt = createProviderToken({keyId: env.APNS_KEY_ID,
    teamId: env.APNS_TEAM_ID, privateKey: key, issuedAt: 1794211200});
  const [header, payload, signature] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url').toString()),
    {alg: 'ES256', kid: env.APNS_KEY_ID});
  assert.deepEqual(JSON.parse(Buffer.from(payload, 'base64url').toString()),
    {iss: env.APNS_TEAM_ID, iat: 1794211200});
  assert.equal(crypto.verify('sha256', Buffer.from(`${header}.${payload}`),
    {key: publicKey, dsaEncoding: 'ieee-p1363'}, Buffer.from(signature, 'base64url')), true);
});

test('APNs notification contains no bets, secrets or user personal data', () => {
  const message = JSON.parse(couponReadyPayload({dayKey: '2026-11-09', coupon}));
  assert.equal(message.kind, 'auto_coupon_ready');
  assert.match(message.aps.alert.body, /4 eventi/);
  assert.equal(JSON.stringify(message).includes('fixtureId'), false);
  assert.equal(JSON.stringify(message).includes('token'), false);
});

test('invalid token or coupon fails closed, never calls APNs', async () => {
  const transport = () => { throw Error('not allowed'); };
  assert.equal((await send({deviceToken: 'not-token', transport})).status,
    'invalid_device_token');
  assert.equal((await send({coupon: {events: []}, transport})).status,
    'invalid_coupon');
  assert.equal((await send({dayKey: '../bad', transport})).status,
    'invalid_coupon');
});

test('push is sent only to Apple sandbox with correct headers and collapse id', async () => {
  const result = await send({transport: async ({origin, headers, payload}) => {
    assert.equal(origin, 'https://api.sandbox.push.apple.com');
    assert.equal(headers[':path'], `/3/device/${deviceToken}`);
    assert.equal(headers['apns-push-type'], 'alert');
    assert.equal(headers['apns-topic'], env.APNS_BUNDLE_ID);
    assert.equal(headers['apns-collapse-id'], 'auto-2026-11-09');
    assert.equal(headers['apns-expiration'], '0');
    assert.match(headers.authorization, /^bearer eyJ/);
    assert.match(payload, /GoalVdLine/);
    return {status: 200};
  }});
  assert.equal(result.status, 'accepted_by_apns');
});

test('Apple acceptance is distinct from device delivery, 410 invalidates token', async () => {
  assert.equal((await send({transport: async () => ({status: 200})})).status,
    'accepted_by_apns');
  assert.equal((await send({transport: async () => ({status: 410})})).status,
    'unregistered_device');
  assert.deepEqual(await send({transport: async () => ({status: 429})}),
    {status: 'rejected_by_apns', httpStatus: 429});
});

test('transport failures do not leak details or credentials', async () => {
  assert.equal((await send({transport: async () => {throw Error('private path');}})).status,
    'transport_error');
});

test('HTTP/2 APNs request transmits payload and safely closes session', async () => {
  let received = '';
  let closed = 0;
  let requestHeaders;
  const connect = origin => {
    assert.equal(origin, 'https://api.push.apple.com');
    const client = new EventEmitter();
    client.close = () => { closed++; };
    client.request = headers => {
      requestHeaders = headers;
      const req = new EventEmitter();
      req.setTimeout = (_ms, _cb) => {};
      req.close = () => { closed++; };
      req.end = data => {
        received = data;
        process.nextTick(() => {
          req.emit('response', {':status': 200});
          req.emit('end');
        });
      };
      return req;
    };
    return client;
  };
  const result = await requestApns({origin: 'https://api.push.apple.com',
    headers: {':method': 'POST'}, payload: 'message', connect});
  assert.equal(received, 'message');
  assert.deepEqual(requestHeaders, {':method': 'POST'});
  assert.equal(result.status, 200);
  assert.equal(closed, 2);
});
