'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const net = require('node:net');
const path = require('node:path');

const backendDir = path.join(__dirname, '..');
const serverPath = path.join(backendDir, 'server.js');
const preloadPath = path.join(__dirname, 'fixtures',
  'football_server_mock_preload.js');

async function unusedLocalPort() {
  const socket = net.createServer();
  await new Promise((resolve, reject) => {
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', resolve);
  });
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  return port;
}

async function startIsolatedAiServer() {
  const port = await unusedLocalPort();
  const base = 'http://127.0.0.1:' + port;
  const child = spawn(process.execPath, ['--require', preloadPath, serverPath], {
    cwd: backendDir,
    env: {
      // No production environment variables, credentials, database access or
      // third-party provider calls are inherited by this process.
      PATH: process.env.PATH || '',
      HOME: process.env.HOME || '',
      NODE_ENV: 'test',
      GOALVDLINE_LOCAL_STAGING_MOCK: 'enabled',
      PORT: String(port),
      OPENAI_API_KEY: 'LOCAL_TEST_ONLY_FAKE_OPENAI_KEY',
      FOOTBALL_API_KEY: 'LOCAL_ONLY_FAKE_KEY',
      PUBLIC_AI_MOBILE_TOKEN_MODE: 'off',
      PUBLIC_FOOTBALL_MOBILE_TOKEN_MODE: 'off',
      LEARNING_SERVER_ENABLED: 'false',
      LEARNING_MOBILE_INGEST_ENABLED: 'false',
      AUTO_COUPON_WORKER_ENABLED: 'false',
      ON_DEMAND_COUPON_WORKER_ENABLED: 'false',
    },
    stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  let output = '';
  let exitCode = null;
  let calls = 0;
  let blockedExternal = 0;
  let commandId = 0;
  const pendingCommands = new Map();

  child.stdout.on('data', data => {
    output = (output + String(data)).slice(-6000);
  });
  child.stderr.on('data', data => {
    output = (output + String(data)).slice(-6000);
  });
  child.on('exit', code => {exitCode = code;});
  child.on('message', msg => {
    if (msg?.from !== 'football-mock') return;
    if (msg.type === 'upstream') calls++;
    if (msg.type === 'blocked-external-fetch') blockedExternal++;
    if (msg.type === 'ack') {
      const waiter = pendingCommands.get(msg.requestId);
      if (waiter) {
        pendingCommands.delete(msg.requestId);
        waiter(msg);
      }
    }
  });

  async function command(command, options = {}) {
    const requestId = ++commandId;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        pendingCommands.delete(requestId);
        reject(Error('Mock command timeout: ' + command));
      }, 3000);
      pendingCommands.set(requestId, reply => {
        clearTimeout(timeout);
        resolve(reply);
      });
      if (!child.connected) {
        clearTimeout(timeout);
        pendingCommands.delete(requestId);
        reject(Error('Test backend exited before mock command'));
      } else {
        child.send({requestId, command, ...options});
      }
    });
  }

  async function request(uri) {
    const response = await fetch(base + uri, {
      signal: AbortSignal.timeout(5000),
    });
    const body = await response.json();
    return {
      status: response.status,
      cache: response.headers.get('x-smartbet-cache'),
      retryAfter: response.headers.get('retry-after'),
      body,
    };
  }

  async function stop() {
    for (const waiter of pendingCommands.values()) {
      waiter({error: 'process stopped'});
    }
    pendingCommands.clear();
    if (exitCode !== null) return;
    const ended = new Promise(resolve => {
      child.once('exit', resolve);
    });
    child.kill('SIGTERM');
    await Promise.race([ended, new Promise(resolve => setTimeout(resolve, 4000))]);
    if (exitCode === null) child.kill('SIGKILL');
  }

  const deadline = Date.now() + 14000;
  let started = false;
  while (Date.now() < deadline) {
    if (exitCode !== null) break;
    try {
      const result = await request('/health');
      if (result.status === 200 && result.body.status === 'ok') {
        started = true;
        break;
      }
    } catch (_) {
      await new Promise(resolve => setTimeout(resolve, 90));
    }
  }
  if (!started) {
    await stop();
    throw Error('Isolated backend failed /health: ' +
      output.replace(/LOCAL_TEST_ONLY_FAKE_OPENAI_KEY|LOCAL_ONLY_FAKE_KEY/g,
        '[REDACTED]'));
  }
  return {
    request, command, stop,
    get calls() {return calls;},
    get blockedExternal() {return blockedExternal;},
    get output() {return output;},
  };
}

async function waitFor(check, limitMs = 2000) {
  const stopAt = Date.now() + limitMs;
  while (Date.now() < stopAt) {
    if (check()) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw Error('Timed out waiting for isolated backend mock event');
}

test('real Express backend on 127.0.0.1: cache, odds, anti429, single probe, safe diagnostics',
  {timeout: 50000}, async () => {
  const ai = await startIsolatedAiServer();
  try {
    // The real server handles these HTTP routes, not a re-implementation.
    const fixtures = await ai.request('/football/fixtures?date=2026-11-19');
    assert.equal(fixtures.status, 200);
    assert.equal(fixtures.cache, 'MISS');
    assert.deepEqual(fixtures.body.response, [{mock: true}]);
    const fixtureCached = await ai.request('/football/fixtures?date=2026-11-19');
    assert.equal(fixtureCached.status, 200);
    assert.equal(fixtureCached.cache, 'HIT');
    assert.equal(ai.calls, 1, 'second request must use actual server cache');

    const league = await ai.request('/football/leagues');
    assert.equal(league.status, 200);
    assert.equal(league.cache, 'MISS');
    const generic = await ai.request('/football/api/fixtures?league=135&season=2026');
    assert.equal(generic.status, 200);
    assert.deepEqual(generic.body.response, [{mock: true}]);

    // Same-key requests share one ongoing provider call.
    const beforeShared = ai.calls;
    const shared = await Promise.all(Array.from({length: 12}, () =>
      ai.request('/football/odds?fixture=77777'),
    ));
    assert.ok(shared.every(v => v.status === 200));
    assert.equal(ai.calls - beforeShared, 1);

    // Twenty distinct fixture IDs must be served using the bounded healthy
    // queue, with no extra network service and <= 4 upstream concurrency.
    const burst = await Promise.all(Array.from({length: 20}, (_, i) =>
      ai.request('/football/odds?fixture=' + (10000+i)),
    ));
    assert.ok(burst.every(x => x.status === 200),
      'healthy burst must not cause local 503');
    const stats = await ai.command('stats');
    assert.ok(stats.maximumInFlight <= 4);
    assert.equal(ai.blockedExternal, 0);

    await ai.command('mode', {value: 'limited'});
    const first429 = await ai.request('/football/odds?fixture=88881');
    assert.equal(first429.status, 502);
    assert.equal(first429.body.code, 'FOOTBALL_PROVIDER_RATE_LIMIT');
    assert.equal(Object.hasOwn(first429.body, 'apiResponse'), false);
    const after429 = ai.calls;

    const blocked = await Promise.all(Array.from({length: 60}, (_, i) =>
      ai.request('/football/odds?fixture=' + (88000 + i)),
    ));
    assert.ok(blocked.every(x =>
      x.status === 503 && x.body.code === 'FOOTBALL_PROVIDER_COOLDOWN' &&
      Number(x.retryAfter) > 0));
    assert.equal(ai.calls, after429);
    assert.equal((await ai.request('/football/fixtures?date=2026-11-19')).status,
      200, 'valid cached data are still available during provider cooldown');

    // Fast-forward ONLY the mock backend clock; no real 2-minute sleep.
    await ai.command('advance', {ms: 120000});
    await ai.command('mode', {value: 'probe_hold'});
    const waitingProbe = ai.request('/football/odds?fixture=99881');
    await waitFor(() => ai.calls === after429 + 1);
    const probeBlocked = await Promise.all(Array.from({length: 24}, (_, i) =>
      ai.request('/football/odds?fixture=' + (99000 + i)),
    ));
    assert.ok(probeBlocked.every(v =>
      v.status === 503 && v.body.code === 'FOOTBALL_PROVIDER_COOLDOWN'));
    assert.equal(ai.calls, after429 + 1);
    await ai.command('release_probe');
    const resumed = await waitingProbe;
    assert.equal(resumed.status, 200);
    const normalAgain = await ai.request('/football/odds?fixture=99882');
    assert.equal(normalAgain.status, 200);
    assert.equal(ai.blockedExternal, 0);

    console.log('[AI-BACKEND-STAGING] Real backend HTTP routes OK; ' +
      '20/20 healthy requests; 60/60 cooldown blocks; ' +
      '24/24 one-probe blocks; cache and single-flight OK; ' +
      'max upstream concurrency <= 4; zero external network fetches.');
  } finally {
    await ai.stop();
  }
});
