'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createBackgroundScheduler} = require('../auto_coupon/background_scheduler');
const {backgroundWorkerConfiguration, main} = require('../auto_coupon/background_worker');

const token = 'x'.repeat(40);
const enabled = {
  AUTO_COUPON_BACKGROUND_ENABLED: 'true',
  AUTO_COUPON_WORKER_ENABLED: 'true',
  AUTO_COUPON_PREFERENCES_ENABLED: 'true',
  AUTO_COUPON_OFFICIAL_ENGINE_ENABLED: 'true',
  AUTO_COUPON_OFFICIAL_ENGINE_URL: 'https://engine.example.org/coupon/jobs',
  AUTO_COUPON_OFFICIAL_ENGINE_TOKEN: token,
  AUTO_COUPON_OFFICIAL_ENGINE_REVISION: 'abcdef1234567',
  DATABASE_URL: 'postgres://test.invalid/not-a-real-database',
};
const cursorA = 'a'.repeat(64);
const cursorB = 'b'.repeat(64);

test('background worker is disabled by default, even with engine credentials', () => {
  assert.equal(backgroundWorkerConfiguration({...enabled,
    AUTO_COUPON_BACKGROUND_ENABLED: undefined}), null);
  for (const missing of ['AUTO_COUPON_WORKER_ENABLED',
    'AUTO_COUPON_PREFERENCES_ENABLED', 'AUTO_COUPON_OFFICIAL_ENGINE_ENABLED',
    'DATABASE_URL', 'AUTO_COUPON_OFFICIAL_ENGINE_TOKEN']) {
    assert.equal(backgroundWorkerConfiguration({...enabled, [missing]: undefined}), null);
  }
});

test('strict background configuration refuses unsafe intervals and invalid URLs', () => {
  assert.deepEqual(backgroundWorkerConfiguration(enabled),
    {intervalMs: 120000, pageSize: 20});
  for (const seconds of ['0', '-2', '20', '1801', 'oops', '1.5']) {
    assert.equal(backgroundWorkerConfiguration({...enabled,
      AUTO_COUPON_BACKGROUND_INTERVAL_SECONDS: seconds}), null);
  }
  assert.equal(backgroundWorkerConfiguration({...enabled,
    AUTO_COUPON_BACKGROUND_PAGE_SIZE: '26'}), null);
  assert.equal(backgroundWorkerConfiguration({...enabled,
    AUTO_COUPON_OFFICIAL_ENGINE_URL: 'http://localhost:5000/coupon/jobs'}), null);
});

test('sequential pagination resumes cursor when bounded and resets at end', async () => {
  const calls = [];
  const batches = [
    {status: 'checked', checked: 1, nextCursor: cursorA},
    {status: 'checked', checked: 1, nextCursor: cursorB},
    {status: 'checked', checked: 0, nextCursor: null},
    {status: 'checked', checked: 0, nextCursor: null},
  ];
  const scheduler = createBackgroundScheduler({runBatch: async input => {
    calls.push(input);
    return batches.shift();
  }, pageSize: 1, maxPagesPerSweep: 2});
  assert.equal((await scheduler.sweep()).status, 'partial');
  assert.equal((await scheduler.sweep()).status, 'completed');
  assert.equal((await scheduler.sweep()).status, 'completed');
  assert.deepEqual(calls.map(c => c.afterSubjectHash),
    [null, cursorA, cursorB, null]);
});

test('overlapping sweeps cannot invoke two batches at once', async () => {
  let release;
  let calls = 0;
  const scheduler = createBackgroundScheduler({runBatch: () => {
    calls++;
    return new Promise(resolve => {release = resolve;});
  }});
  const first = scheduler.sweep();
  assert.deepEqual(await scheduler.sweep(), {status: 'busy'});
  release({status: 'checked', checked: 0, nextCursor: null});
  await first;
  assert.equal(calls, 1);
});

test('invalid page, repeated cursor and backend failures fail closed', async () => {
  const invalid = createBackgroundScheduler({runBatch: async () => ({status:'ok'})});
  await assert.rejects(invalid.sweep(), /Invalid coordinator batch result/);
  const repeated = createBackgroundScheduler({pageSize: 1,
    runBatch: async () => ({status:'checked', checked:1, nextCursor:cursorA})});
  await assert.rejects(repeated.sweep(), /did not advance/);
});

test('start runs without HTTP, timer errors are sanitized, stop prevents future runs', async () => {
  let tick;
  let clearCount = 0;
  let calls = 0;
  const events = [];
  const scheduler = createBackgroundScheduler({
    runBatch: async () => {
      calls++;
      if (calls > 1) throw new Error('secret provider failure');
      return {status:'checked', checked:0, nextCursor:null};
    },
    onError: value => events.push(value),
    setIntervalFn: cb => {tick = cb; return 10;},
    clearIntervalFn: () => {clearCount++;},
  });
  assert.equal((await scheduler.start()).status, 'completed');
  tick();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(events, ['cycle_failed']);
  await scheduler.stop();
  assert.equal(clearCount, 1);
  assert.deepEqual(await scheduler.sweep(), {status:'stopped'});
});

test('invalid scheduler settings are rejected', () => {
  assert.throws(() => createBackgroundScheduler({runBatch:()=>{}, intervalMs:1}));
  assert.throws(() => createBackgroundScheduler({runBatch:()=>{}, pageSize:26}));
  assert.throws(() => createBackgroundScheduler({runBatch:()=>{}, maxPagesPerSweep:0}));
});


test('standalone main uses existing Neon coordinator without an HTTP listener', async () => {
  let initialized = 0;
  let listed = 0;
  let closed = 0;
  const signals = [];
  const worker = await main({env:enabled,
    poolFactory: () => ({end: async () => {closed++;}}),
    repositoryFactory: () => ({
      initialize: async () => {initialized++;},
      listAutoCouponSubscribers: async () => {listed++; return [];},
    }),
    engineFactory: () => async () => {throw new Error('No actual engine requested');},
    schedulerFactory: opts => ({
      start: () => opts.runBatch({limit:opts.pageSize, afterSubjectHash:null}),
      stop: async () => {},
    }),
    processRef: {once: signal => signals.push(signal)},
  });
  assert.ok(worker);
  assert.equal(initialized, 2);
  assert.equal(listed, 1);
  assert.equal(closed, 0);
  assert.deepEqual(signals, ['SIGTERM', 'SIGINT']);
});

test('standalone worker fails closed before database is opened when disabled', async () => {
  let opened = false;
  await assert.rejects(main({env: {}, poolFactory: () => {opened = true;}}),
    /disabled or misconfigured/);
  assert.equal(opened, false);
});
