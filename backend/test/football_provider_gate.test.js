'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createFootballProviderGate} = require('../football_provider_gate');
const {
  footballFailurePayload,
  respondFootballFailure,
} = require('../football_upstream_diagnostics');

function provider429() {
  const err = new Error('Provider throttled: upstream secret should never be returned');
  err.code = 'FOOTBALL_PROVIDER_RATE_LIMIT';
  err.statusCode = 502;
  err.upstreamStatus = 429;
  return err;
}

test('first provider 429 opens cooldown across different routes, no more upstream calls', async () => {
  let now = 0;
  let called = 0;
  const gate = createFootballProviderGate({
    now: () => now, maxConcurrent: 4,
    baseCooldownMs: 60000, maxCooldownMs: 600000,
  });
  await assert.rejects(gate.run(async () => {
    called++; throw provider429();
  }), {code:'FOOTBALL_PROVIDER_RATE_LIMIT'});
  for (let i = 0; i < 20; i++) {
    await assert.rejects(gate.run(async () => {
      called++;return {route:i};
    }), {code:'FOOTBALL_PROVIDER_COOLDOWN',statusCode:503});
  }
  assert.equal(called,1);
  now = 59999;
  await assert.rejects(gate.run(() => {called++;}), {code:'FOOTBALL_PROVIDER_COOLDOWN'});
  assert.equal(called,1);
});

test('one successful probe reopens circuit after cooldown', async () => {
  let now = 1000, calls=0;
  const gate=createFootballProviderGate({
    now:()=>now, baseCooldownMs:1000,maxCooldownMs:8000,
  });
  await assert.rejects(gate.run(async()=>{calls++;throw provider429();}),
    {code:'FOOTBALL_PROVIDER_RATE_LIMIT'});
  now=2000;
  let release;
  const pending=gate.run(async()=>{calls++;return await new Promise(resolve=>{release=resolve;});});
  await assert.rejects(gate.run(async()=>{calls++;}),{code:'FOOTBALL_PROVIDER_COOLDOWN'});
  assert.equal(calls,2);
  release({ok:true});
  assert.deepEqual(await pending,{ok:true});
  assert.deepEqual(await gate.run(async()=>{calls++;return {recovered:true};}),{recovered:true});
  assert.equal(calls,3);
});

test('repeated provider 429s back off exponentially with cap', async () => {
  let now=0,calls=0;
  const gate=createFootballProviderGate({
    now:()=>now,baseCooldownMs:1000,maxCooldownMs:4000,
  });
  const failed=async()=>{calls++;throw provider429();};
  await assert.rejects(gate.run(failed),{code:'FOOTBALL_PROVIDER_RATE_LIMIT'});
  now=1000;
  await assert.rejects(gate.run(failed),{code:'FOOTBALL_PROVIDER_RATE_LIMIT'});
  now=2000;
  await assert.rejects(gate.run(failed),{code:'FOOTBALL_PROVIDER_COOLDOWN'});
  now=3000;
  await assert.rejects(gate.run(failed),{code:'FOOTBALL_PROVIDER_RATE_LIMIT'});
  now=6000;
  await assert.rejects(gate.run(failed),{code:'FOOTBALL_PROVIDER_COOLDOWN'});
  now=7000;
  await assert.rejects(gate.run(failed),{code:'FOOTBALL_PROVIDER_RATE_LIMIT'});
  assert.equal(calls,4);
});

test('global provider concurrency stops storms on different fixture IDs', async () => {
  const gate=createFootballProviderGate({maxConcurrent:2});
  const releases=[];
  let total=0;
  const makeRequest=()=>gate.run(async()=>{
    total++;
    return new Promise(resolve=>releases.push(resolve));
  });
  const first=makeRequest();
  const second=makeRequest();
  await assert.rejects(makeRequest(),{code:'FOOTBALL_PROVIDER_BUSY',statusCode:503});
  assert.equal(total,2);
  releases.forEach((release,i)=>release(i+1));
  assert.deepEqual(await Promise.all([first,second]),[1,2]);
  assert.equal(await gate.run(async()=>3),3);
});

test('network failure of recovery probe delays another attempt; no stampede', async () => {
  let now=0;
  const gate=createFootballProviderGate({
    now:()=>now,baseCooldownMs:1000,maxCooldownMs:8000,
  });
  await assert.rejects(gate.run(async()=>{throw provider429();}));
  now=1000;
  await assert.rejects(gate.run(async()=>{throw new Error('network disconnected');}),
    /network disconnected/);
  now=1500;
  await assert.rejects(gate.run(async()=>1),{code:'FOOTBALL_PROVIDER_COOLDOWN'});
  now=2000;
  assert.equal(await gate.run(async()=>42),42);
});

test('successful in-flight response cannot erase a newer provider 429 block', async () => {
  let now=0;
  const gate=createFootballProviderGate({
    now:()=>now,baseCooldownMs:1000,maxCooldownMs:8000,
  });
  let release;
  const older=gate.run(()=>new Promise(resolve=>{release=resolve;}));
  await assert.rejects(gate.run(async()=>{throw provider429();}),
    {code:'FOOTBALL_PROVIDER_RATE_LIMIT'});
  release('older cached');
  assert.equal(await older,'older cached');
  await assert.rejects(gate.run(async()=>1),{code:'FOOTBALL_PROVIDER_COOLDOWN'});
});

test('cached data and same-key single-flight remain before provider guard in server',()=>{
  const s=fs.readFileSync(path.join(__dirname,'..','server.js'),'utf8');
  const start=s.indexOf('async function requestApiFootball(');
  const cache=s.indexOf('const cached = getFootballCache(cacheKey)',start);
  const single=s.indexOf('const existingRequest =',cache);
  const guarded=s.indexOf('footballProviderGate.run(',single);
  assert.ok(start>0 && cache>start && single>cache && guarded>single);
});

test('cooldown response uses Retry-After and does not expose raw provider details',()=>{
  const error=new Error('REMOTE_KEY=secret');
  error.code='FOOTBALL_PROVIDER_COOLDOWN';
  error.statusCode=503;
  error.retryAfterSeconds=85;
  const response={
    statusCode:200,headers:{},body:null,
    status(n){this.statusCode=n;return this;},
    set(k,v){this.headers[k]=v;return this;},
    json(b){this.body=b;return this;},
  };
  const oldWarn=console.warn;console.warn=()=>{};
  try{respondFootballFailure(response,error,'/odds');}finally{console.warn=oldWarn;}
  assert.equal(response.statusCode,503);
  assert.equal(response.body.code,'FOOTBALL_PROVIDER_COOLDOWN');
  assert.equal(response.headers['Retry-After'],'85');
  assert.doesNotMatch(JSON.stringify(response.body),/REMOTE_KEY|secret/);
  assert.equal(footballFailurePayload(error).httpStatus,503);
});

test('invalid gate config rejected instead of disabling protections',()=>{
  assert.throws(()=>createFootballProviderGate({maxConcurrent:0}));
  assert.throws(()=>createFootballProviderGate({baseCooldownMs:0}));
  assert.throws(()=>createFootballProviderGate({maxCooldownMs:1000,baseCooldownMs:2000}));
});


test('healthy spike: bounded FIFO queue serves 18 requests with just two provider slots', async () => {
  let inFlight = 0;
  let maximum = 0;
  let upstream = 0;
  const gate = createFootballProviderGate({
    maxConcurrent: 2,
    maxQueue: 20,
    maxWaitMs: 2000,
  });
  const tasks = Array.from({length: 18}, (_, i) => gate.run(async () => {
    upstream++;
    inFlight++;
    maximum = Math.max(maximum, inFlight);
    await new Promise(resolve => setTimeout(resolve, 3));
    inFlight--;
    return i;
  }));
  const results = await Promise.all(tasks);
  assert.deepEqual(results, Array.from({length:18}, (_, i) => i));
  assert.equal(maximum, 2);
  assert.equal(upstream, 18);
});

test('upstream 429 cancels waiting queue without sending queued provider requests', async () => {
  let rejectFirst;
  let upstream = 0;
  const gate = createFootballProviderGate({
    maxConcurrent: 1,
    maxQueue: 12,
    maxWaitMs: 2000,
    baseCooldownMs: 1000,
    maxCooldownMs: 4000,
  });
  const first = gate.run(() => {
    upstream++;
    return new Promise((resolve, reject) => {rejectFirst = reject;});
  });
  const waiting = Array.from({length: 10}, () => gate.run(async () => {
    upstream++;
    return {shouldNotRun: true};
  }));
  const combined = Promise.allSettled([first, ...waiting]);
  rejectFirst(provider429());
  const results = await combined;
  assert.equal(results[0].status, 'rejected');
  assert.equal(results[0].reason.code, 'FOOTBALL_PROVIDER_RATE_LIMIT');
  assert.equal(results.slice(1).filter(x => x.status === 'rejected' &&
      x.reason.code === 'FOOTBALL_PROVIDER_COOLDOWN').length, 10);
  assert.equal(upstream, 1);
});

test('full queue and queue timeout return safe busy status without leaking slots', async () => {
  const gate = createFootballProviderGate({
    maxConcurrent: 1,
    maxQueue: 1,
    maxWaitMs: 1000,
  });
  let release;
  const first = gate.run(() => new Promise(resolve => {release = resolve;}));
  const second = gate.run(async () => 2);
  const third = gate.run(async () => 3);
  await assert.rejects(third, {code:'FOOTBALL_PROVIDER_BUSY'});
  release(1);
  assert.deepEqual(await Promise.all([first, second]), [1, 2]);
  assert.equal(await gate.run(async () => 4), 4);
});

test('invalid queue bounds rejected rather than silently disabling them', () => {
  assert.throws(() => createFootballProviderGate({maxQueue:-1}));
  assert.throws(() => createFootballProviderGate({maxQueue:501}));
  assert.throws(() => createFootballProviderGate({maxWaitMs:0}));
});
