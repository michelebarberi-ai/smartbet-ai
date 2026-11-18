'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const {createFootballProviderGate} = require('../football_provider_gate');
const {fetchFootballJson, footballFailurePayload} = require('../football_upstream_diagnostics');

// Simulated HTTP client/server integration. There are ZERO requests to the
// real Render service, API-Football, Neon or OpenAI; only 127.0.0.1 is used.
// Exercises the same anti-429 components as the production proxy.
test('isolated HTTP staging: 180 requests across markets never stampede an upstream 429',
  {timeout: 25000}, async () => {
  let clock = 1_000_000;
  let upstreamCalls = 0;
  let upstreamInFlight = 0;
  let maxObservedUpstream = 0;
  let state = 'limited';
  let startProbe;
  let releaseProbe;
  const probeStarted = new Promise(resolve => {startProbe = resolve;});
  const probeResponse = new Promise(resolve => {releaseProbe = resolve;});

  const gate = createFootballProviderGate({
    now: () => clock,
    maxConcurrent: 4,
    maxQueue: 32,
    maxWaitMs: 8000,
    baseCooldownMs: 1000,
    maxCooldownMs: 4000,
  });

  const fakeProvider = async () => {
    upstreamCalls++;
    upstreamInFlight++;
    maxObservedUpstream = Math.max(maxObservedUpstream, upstreamInFlight);
    try {
      if (state === 'limited') {
        return {
          ok: false,
          status: 429,
          text: async () => '{"errors":{"requests":"Too many requests"}}',
        };
      }
      if (state === 'probe_hold') {
        startProbe();
        return await probeResponse;
      }
      await new Promise(resolve => setTimeout(resolve, 8));
      return {
        ok: true,
        status: 200,
        text: async () => '{"response":[{"ok":true}],"errors":{}}',
      };
    } finally {
      upstreamInFlight--;
    }
  };

  const cache = new Map([
    ['/fixtures?date=known', {
      payload: {response: [{fixture: 'cached-only'}], errors: {}},
      expiresAt: clock + 100000,
    }],
    ['/fixtures?date=expired', {
      payload: {response: [{fixture: 'stale-must-not-be-served'}], errors: {}},
      expiresAt: clock - 1,
    }],
  ]);
  const server = http.createServer(async (req, res) => {
    const key = req.url;
    const cached = cache.get(key);
    if (cached && clock < cached.expiresAt) {
      res.writeHead(200, {'Content-Type': 'application/json'});
      res.end(JSON.stringify(cached.payload));
      return;
    }
    try {
      const payload = await gate.run(() => fetchFootballJson({
        url: 'https://example.invalid/football' + key,
        apiKey: 'FAKE_STAGING_KEY',
        fetchImpl: fakeProvider,
        timeoutMs: 1000,
      }));
      res.writeHead(200, {'Content-Type': 'application/json'});
      res.end(JSON.stringify(payload));
    } catch (error) {
      const output = footballFailurePayload(error);
      const headers = {'Content-Type': 'application/json'};
      if (error.retryAfterSeconds) {
        headers['Retry-After'] = String(error.retryAfterSeconds);
      }
      res.writeHead(output.httpStatus, headers);
      res.end(JSON.stringify(output.body));
    }
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const base = 'http://127.0.0.1:' + server.address().port;
  const request = async (endpoint) => {
    const response = await fetch(base + endpoint);
    return {status: response.status, json: await response.json(),
      retryAfter: response.headers.get('retry-after')};
  };

  try {
    const first = await request('/football/odds?fixture=1');
    assert.equal(first.status, 502);
    assert.equal(first.json.code, 'FOOTBALL_PROVIDER_RATE_LIMIT');
    assert.equal(upstreamCalls, 1);

    const burst = await Promise.all(Array.from({length: 180}, (_, i) =>
      request('/football/' + ['fixtures', 'odds', 'injuries', 'lineups',
        'statistics', 'events'][i % 6] + '?fixture=' + (i+2)),
    ));
    assert.equal(burst.length, 180);
    assert.equal(burst.filter(r => r.status === 503).length, 180);
    assert.equal(burst.filter(r =>
      r.json.code === 'FOOTBALL_PROVIDER_COOLDOWN').length, 180);
    assert.equal(upstreamCalls, 1,
      '180 distinct URLs must not create 180 upstream requests');
    assert.ok(burst.every(r => Number(r.retryAfter) >= 1));

    const cached = await request('/fixtures?date=known');
    assert.equal(cached.status, 200);
    assert.equal(cached.json.response[0].fixture, 'cached-only');
    const expired = await request('/fixtures?date=expired');
    assert.equal(expired.status, 503);
    assert.equal(upstreamCalls, 1);
    assert.ok(!JSON.stringify(expired.json).includes('stale-must-not-be-served'));

    clock += 1000;
    state = 'probe_hold';
    const probe = request('/football/fixtures?date=after-cooldown');
    await probeStarted;
    const blockedDuringProbe = await Promise.all(Array.from({length: 45}, (_, i) =>
      request('/football/odds?fixture=probe' + i),
    ));
    assert.ok(blockedDuringProbe.every(r =>
      r.status === 503 && r.json.code === 'FOOTBALL_PROVIDER_COOLDOWN'));
    assert.equal(upstreamCalls, 2, 'only one probe can reach provider');
    releaseProbe({
      ok: true, status: 200,
      text: async () => '{"response":[{"fixture":"probe-ok"}],"errors":{}}',
    });
    const successProbe = await probe;
    assert.equal(successProbe.status, 200);
    assert.equal(successProbe.json.response[0].fixture, 'probe-ok');

    state = 'healthy';
    const recovered = await request('/football/leagues?current=true');
    assert.equal(recovered.status, 200);
    assert.equal(upstreamCalls, 3);

    // Normal traffic: 20 distinct fixture+market requests while the
    // provider is HEALTHY. The FIFO queue should avoid immediate 503s
    // without sending more than four upstream requests concurrently.
    const healthyBurst = await Promise.all(Array.from({length: 20}, (_, i) =>
      request('/football/fixtures?date=healthy-' + i),
    ));
    assert.equal(healthyBurst.length, 20);
    assert.ok(healthyBurst.every(r => r.status === 200),
      'healthy requests should be queued and served, not dropped');
    assert.equal(upstreamCalls, 23);
    assert.ok(maxObservedUpstream <= 4,
      'provider upstream concurrency never exceeds four');

    console.log('[STAGING-SIMULATION] 180 unique requests: 1 upstream 429, ' +
      '180 local cooldown responses, 0 extra provider calls. ' +
      'Cached item 200, expired item 503, 45 during probe blocked, ' +
      'one probe succeeded, recovered 200. 20 healthy concurrent requests ' +
      'all succeeded, upstream concurrency <= 4. No production traffic.');
  } finally {
    if (typeof releaseProbe === 'function') {
      releaseProbe({
        ok:true, status:200,
        text:async ()=>'{"response":[],"errors":{}}',
      });
    }
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
