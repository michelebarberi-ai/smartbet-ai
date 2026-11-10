'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {AutoCouponGenerationCoordinator} = require('../auto_coupon/generation_coordinator');

const subjectHash = '1'.repeat(64);
const anotherHash = '2'.repeat(64);
const now = new Date('2026-11-09T08:15:00Z'); // Rome 09:15
const preferences = Object.freeze({requested: true, hour: 8, minute: 0, events: 3,
  minimumMarketProbability: 65, market: 'MULTI', notifyChanges: true});
const validCoupon = {events: [1, 2, 3].map((n) => ({
  fixtureId: n, market: 'OVER_UNDER', marketProbability: 75,
  kickoffAt: '2026-11-09T18:00:00Z', odds: 1.83,
  hiddenPII: 'MUST_NOT_PERSIST',
}))};
function makeRepo() {
  const claimed = [];
  const completed = [];
  let init = 0;
  return {claimed, completed, get init(){return init;},
    async initialize(){init++;},
    async renewAutoCouponLease(){return true;},
    async claimAutoCouponRun(args){claimed.push(args); return {attempts: 1, leaseToken: '11111111-1111-4111-8111-111111111111'};},
    async finishAutoCouponRun(args){completed.push(args);return true;},
    async listAutoCouponSubscribers(limit,cursor){
      assert.equal(limit, 2);
      assert.equal(cursor, null);
      return [{subjectHash,preferences},{subjectHash:anotherHash,preferences}];
    },
  };
}
const coordinator = (repo, generator, instant = now) =>
  new AutoCouponGenerationCoordinator({repository:repo,generateOfficialCoupon:generator,now:()=>instant});

test('cannot start without official generation engine or database work',async()=>{
  const repo=makeRepo();
  assert.deepEqual(await coordinator(repo, null).runOne({subjectHash,preferences}),
    {status:'official_engine_not_connected'});
  assert.equal(repo.init,0);
  assert.equal((await coordinator(repo,null).runBatch()).checked,0);
});

test('invalid, disabled and future schedule never invoke the generator',async()=>{
  const repo=makeRepo(); let called=0;
  const worker=coordinator(repo,async()=>{called++;return validCoupon;});
  assert.equal((await worker.runOne({subjectHash:'bad',preferences})).status,'invalid_subject');
  assert.equal((await worker.runOne({subjectHash,preferences:{...preferences,requested:false}})).reason,'disabled');
  assert.equal((await worker.runOne({subjectHash,preferences:{...preferences,hour:20}})).reason,'before_scheduled_time');
  assert.equal(called,0); assert.equal(repo.claimed.length,0);
});

test('verified coupon stored with only minimal fields',async()=>{
  const repo=makeRepo();
  const result=await coordinator(repo,async()=>validCoupon).runOne({subjectHash,preferences});
  assert.deepEqual(result,{status:'ready',dayKey:'2026-11-09'});
  assert.equal(repo.completed.length,1);
  assert.equal(repo.completed[0].outcome,'ready');
  assert.equal(repo.completed[0].coupon.events.length,3);
  assert.equal('hiddenPII' in repo.completed[0].coupon.events[0],false);
});

test('below threshold, duplicate match and insufficient coupon retry, never save',async()=>{
  for(const bad of [
    {events:validCoupon.events.slice(0,2)},
    {events:validCoupon.events.map((e,i)=>({...e,marketProbability:i===0?10:75}))},
    {events:validCoupon.events.map((e,i)=>({...e,fixtureId:i===2?1:e.fixtureId}))},
  ]) {
    const repo=makeRepo();
    const result=await coordinator(repo,async()=>bad).runOne({subjectHash,preferences});
    assert.equal(result.status,'retry'); assert.equal(result.reason,'insufficient_events');
    assert.equal(repo.completed[0].coupon ?? null,null);
    assert.equal(repo.completed[0].retryMinutes,60);
  }
});

test('generator errors become retry without exposing exception messages',async()=>{
  const repo=makeRepo();
  const result=await coordinator(repo,async()=>{throw Error('PRIVATE TOKEN!');})
    .runOne({subjectHash,preferences});
  assert.deepEqual(result,{status:'retry',reason:'provider_unavailable'});
  assert.equal(repo.completed[0].reason,'provider_unavailable');
  assert.equal(JSON.stringify(repo.completed).includes('PRIVATE TOKEN'),false);
});

test('existing claim is never overwritten or generated twice',async()=>{
  const repo=makeRepo(); repo.claimAutoCouponRun=async()=>null;
  let calls=0;
  const result=await coordinator(repo,async()=>{calls++;return validCoupon;})
    .runOne({subjectHash,preferences});
  assert.equal(result.status,'already_claimed_or_not_due');assert.equal(calls,0);
});

test('failed claim update returns superseded, not fake ready',async()=>{
  const repo=makeRepo();repo.finishAutoCouponRun=async()=>false;
  const result=await coordinator(repo,async()=>validCoupon).runOne({subjectHash,preferences});
  assert.equal(result.status,'superseded');
});

test('batch processes enabled subscribers with a stable cursor',async()=>{
  const repo=makeRepo();
  const result=await coordinator(repo,async()=>validCoupon).runBatch({limit:2});
  assert.equal(result.checked,2); assert.equal(result.results.ready,2);
  assert.equal(result.nextCursor,anotherHash);
});

test('batch limit and cursor are validated',async()=>{
  const worker=coordinator(makeRepo(),async()=>validCoupon);
  await assert.rejects(()=>worker.runBatch({limit:101}),RangeError);
  await assert.rejects(()=>worker.runBatch({limit:1,afterSubjectHash:'bad'}),RangeError);
});

test('coupon is not saved if matches start while official engine computes',async()=>{
  const repo=makeRepo();
  let instant=now;
  const worker=new AutoCouponGenerationCoordinator({repository:repo,
    now:()=>instant,generateOfficialCoupon:async()=>{
      instant=new Date('2026-11-09T18:01:00Z');
      return validCoupon;
    }});
  const outcome=await worker.runOne({subjectHash,preferences});
  assert.equal(outcome.status,'retry');
  assert.equal(repo.completed[0].outcome,'retry');
  assert.equal(repo.completed[0].coupon,undefined);
});
