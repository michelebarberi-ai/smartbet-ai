'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {EventEmitter} = require('node:events');
const crypto = require('node:crypto');

const {
  createPublicApiGuard,
  createLearningMobileAuthenticator,
} = require('../public_api_access_guard');

class Response extends EventEmitter {
  constructor() { super(); this.code = 200; this.headers = {}; this.body = null; }
  status(value) { this.code = value; return this; }
  set(name, value) { this.headers[name] = value; return this; }
  json(value) { this.body = value; this.emit('finish'); return this; }
}
async function invoke(guard, {ip = '192.0.2.1', auth = '',
  spoofed = '', complete = true} = {}) {
  const req = {
    ip, socket: {remoteAddress: ip},
    get(key) { return key === 'authorization' ? auth :
      key === 'x-forwarded-for' ? spoofed : ''; },
  };
  const res = new Response();
  let allowed = false;
  await guard(req, res, () => {
    allowed = true;
    if (complete) res.emit('finish');
  });
  return {allowed, res};
}

test('AI budget: pre-existing iPhone without token still works, up to a bound', async () => {
  let now = 2000000000000;
  const guard = createPublicApiGuard({
    now: () => now,
    env: {PUBLIC_AI_CLIENT_HOURLY_LIMIT: '2',
      PUBLIC_AI_GLOBAL_DAILY_LIMIT: '3'},
  });
  assert.equal((await invoke(guard)).allowed, true);
  assert.equal((await invoke(guard)).allowed, true);
  const blocked = await invoke(guard);
  assert.equal(blocked.allowed, false);
  assert.equal(blocked.res.code, 429);
  assert.equal(blocked.res.body.code, 'AI_RATE_LIMITED');
  assert.ok(Number(blocked.res.headers['Retry-After']) > 0);
  assert.equal((await invoke(guard, {ip: '192.0.2.2'})).allowed, true);
  assert.equal((await invoke(guard, {ip: '192.0.2.3'})).res.code, 429);
  now += 24 * 60 * 60 * 1000;
  assert.equal((await invoke(guard)).allowed, true);
});

test('client IP is not read from untrusted X-Forwarded-For header', async () => {
  const guard = createPublicApiGuard({
    env: {PUBLIC_AI_CLIENT_HOURLY_LIMIT: '1'},
  });
  assert.equal((await invoke(guard, {spoofed: '1.2.3.4'})).allowed, true);
  assert.equal((await invoke(guard, {spoofed: '5.6.7.8'})).res.code, 429);
});

test('concurrency released exactly once for finish and close', async () => {
  const guard = createPublicApiGuard({
    env: {PUBLIC_AI_MAX_CONCURRENT: '1'},
  });
  const pending = await invoke(guard, {complete: false});
  assert.equal(pending.allowed, true);
  assert.equal((await invoke(guard, {ip: '192.0.2.2'})).res.code, 429);
  pending.res.emit('finish');
  pending.res.emit('close');
  assert.equal((await invoke(guard, {ip: '192.0.2.2'})).allowed, true);
});

test('mobile mode requires verified server-issued bearer token', async () => {
  const token = 'T'.repeat(43);
  const guard = createPublicApiGuard({
    tokenMode: 'require',
    env: {PUBLIC_AI_CLIENT_HOURLY_LIMIT: '1'},
    authenticate: async supplied => supplied === token ? 'client-A' : null,
  });
  assert.equal((await invoke(guard)).res.code, 401);
  assert.equal((await invoke(guard, {auth: 'Bearer ' + 'X'.repeat(43)})).res.code, 401);
  assert.equal((await invoke(guard, {auth: 'Bearer ' + token})).allowed, true);
  // Same authenticated install even when source IP changes.
  assert.equal((await invoke(guard, {
    ip: '203.0.113.5', auth: 'Bearer ' + token,
  })).res.code, 429);
});

test('token verifier unavailable always fails closed, does not silently disable auth', async () => {
  const requireMode = createPublicApiGuard({tokenMode: 'require'});
  assert.equal((await invoke(requireMode)).res.code, 503);
  const failing = createPublicApiGuard({
    tokenMode: 'require',
    authenticate: async () => { throw new Error('db unavailable'); },
  });
  assert.equal((await invoke(failing, {
    auth: 'Bearer ' + 'T'.repeat(43),
  })).res.code, 503);
});

test('database verifier queries hashed existing credential, not its plaintext', async () => {
  let queryArgs;
  const token = 'A'.repeat(43);
  const verifier = createLearningMobileAuthenticator({
    env: {PUBLIC_API_AUTH_DATABASE_URL: 'postgresql://tests'},
    now: () => new Date('2026-11-18T00:00:00Z'),
    poolFactory: () => ({
      query: async (_sql, args) => {
        queryArgs = args;
        return {rows: [{client_id: 'real-install-42'}]};
      },
    }),
  });
  assert.equal(await verifier(token), 'real-install-42');
  assert.equal(queryArgs[0], crypto.createHash('sha256').update(token).digest('hex'));
  assert.equal(queryArgs[0].includes(token), false);
  assert.equal(await verifier('bad'), null);
});

test('football uses its own budget and does not require a mobile token by default', async () => {
  const football = createPublicApiGuard({
    group: 'football',
    env: {PUBLIC_FOOTBALL_CLIENT_MINUTE_LIMIT: '1'},
  });
  assert.equal((await invoke(football)).allowed, true);
  assert.equal((await invoke(football)).res.code, 429);
});

test('invalid configuration cannot silently disable token enforcement', () => {
  assert.throws(() => createPublicApiGuard({tokenMode: 'enabled'}));
});
