'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {LearningRepository} = require('../learning/learning_repository');
const {AutoCouponGenerationCoordinator} = require('../auto_coupon/generation_coordinator');

const HASH='f'.repeat(64);
const DAY='2026-11-09';
const NOW=new Date('2026-11-09T08:15:00Z');
const PREFERENCES={requested:true,hour:8,minute:0,events:3,
  minimumMarketProbability:65,market:'MULTI',notifyChanges:true};
const coupon={events:[1,2,3].map(fixtureId=>({fixtureId,market:'OVER 2.5',
  marketProbability:76,odds:1.7,kickoffAt:'2026-11-09T19:00:00Z'}))};
const deferred=()=>{let release;const promise=new Promise(resolve=>{release=resolve;});
  return {promise,release};};

function sqlPool(responses) {
  const calls=[];
  return {calls,async query(sql,args){calls.push({sql,args});return responses.shift() ??
    {rowCount:0,rows:[]};}};
}

test('Neon schema adds lease fields without deleting existing ready coupons',()=>{
  const fs=require('node:fs');const path=require('node:path');
  const sql=fs.readFileSync(path.join(__dirname,'../learning/learning_schema.sql'),'utf8');
  assert.match(sql,/ADD COLUMN IF NOT EXISTS lease_token UUID/);
  assert.match(sql,/ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ/);
  assert.match(sql,/CREATE INDEX IF NOT EXISTS sb_auto_coupon_processing_lease_v1/);
  assert.doesNotMatch(sql,/DROP TABLE|TRUNCATE TABLE/i);
});

test('Neon claim is atomic, fenced, only retries expired leases and does not overwrite READY',async()=>{
  const returnedToken=randomUUID();
  const pool=sqlPool([{rowCount:1,rows:[{attempts:2,leaseToken:returnedToken}]},
    {rowCount:0,rows:[]}]);
  const repo=new LearningRepository(pool);
  const claim=await repo.claimAutoCouponRun({subjectHash:HASH,dayKey:DAY,now:NOW});
  assert.deepEqual(claim,{attempts:2,leaseToken:returnedToken});
  const {sql,args}=pool.calls[0];
  assert.match(sql,/ON CONFLICT \(subject_hash,local_day\) DO UPDATE/);
  assert.match(sql,/attempts < 5/);
  assert.match(sql,/status='retry'/);
  assert.match(sql,/status='processing'/);
  assert.match(sql,/lease_expires_at <= clock_timestamp\(\)/);
  assert.match(sql,/RETURNING attempts, lease_token AS "leaseToken"/);
  assert.deepEqual(args.slice(0,2),[HASH,DAY]);
  assert.match(args[2],/^[\da-f-]{36}$/);
  assert.equal(await repo.claimAutoCouponRun({subjectHash:HASH,dayKey:DAY}),null);
});

test('Neon renewal and final writes use attempt + token + unexpired lease + active consent',async()=>{
  const token=randomUUID();
  const pool=sqlPool([{rowCount:1},{rowCount:1},{rowCount:0}]);
  const repo=new LearningRepository(pool);
  assert.equal(await repo.renewAutoCouponLease({subjectHash:HASH,dayKey:DAY,
    attempts:1,leaseToken:token}),true);
  assert.match(pool.calls[0].sql,/attempts=\$3 AND lease_token=\$4::uuid/);
  assert.match(pool.calls[0].sql,/lease_expires_at > clock_timestamp\(\)/);
  assert.match(pool.calls[0].sql,/p\.preferences->>'requested'='true'/);
  assert.equal(await repo.finishAutoCouponRun({subjectHash:HASH,dayKey:DAY,
    attempts:1,leaseToken:token,outcome:'ready',coupon,now:NOW}),true);
  const {sql,args}=pool.calls[1];
  assert.match(sql,/attempts=\$3 AND lease_token=\$9::uuid/);
  assert.match(sql,/lease_expires_at > clock_timestamp\(\)/);
  assert.match(sql,/p\.preferences->>'requested'='true'/);
  assert.match(sql,/lease_token=NULL, lease_expires_at=NULL/);
  assert.equal(args[8],token);
  // A stale process must accept an unsuccessful UPDATE, never claim it saved a coupon.
  assert.equal(await repo.finishAutoCouponRun({subjectHash:HASH,dayKey:DAY,
    attempts:1,leaseToken:token,outcome:'ready',coupon,now:NOW}),false);
});

function makeRepository() {
  let owned=null;let attempts=0;let saved=null;let enabled=true;
  const stats={claims:0,renewals:0,completions:0};
  const repository={stats,
    async initialize(){},
    async claimAutoCouponRun(){
      if(!enabled || owned) return null;
      attempts++;stats.claims++;
      owned={attempts,leaseToken:randomUUID()};
      return {...owned};
    },
    async renewAutoCouponLease(lease){
      stats.renewals++;
      return enabled && owned?.attempts===lease.attempts &&
        owned?.leaseToken===lease.leaseToken;
    },
    async finishAutoCouponRun(lease){
      if(!enabled || owned?.attempts!==lease.attempts ||
        owned?.leaseToken!==lease.leaseToken) return false;
      stats.completions++;saved=lease.outcome==='ready'?lease.coupon:null;
      owned=null;return true;
    },
    // Simulate a crashed/expired worker, allowing the next one to re-claim.
    expire(){owned=null;},
    disable(){enabled=false;},
    get saved(){return saved;},
  };
  return repository;
}
const worker=(repo,generator,renewMs=60_000)=>new AutoCouponGenerationCoordinator({
  repository:repo,now:()=>NOW,generateOfficialCoupon:generator,leaseRenewalMs:renewMs});
const request={subjectHash:HASH,preferences:PREFERENCES};

test('two concurrent coordinators share Neon claim: only one launches official engine',async()=>{
  const repo=makeRepository();const hold=deferred();let calls=0;
  const first=worker(repo,async()=>{calls++;await hold.promise;return coupon;});
  const second=worker(repo,async()=>{calls++;return coupon;});
  const firstRun=first.runOne(request);
  // Claim's async work may still be pending in first run.
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal((await second.runOne(request)).status,'already_claimed_or_not_due');
  hold.release();
  assert.equal((await firstRun).status,'ready');
  assert.equal(calls,1);
  assert.equal(repo.stats.completions,1);
});

test('heartbeat protects long-running official generation beyond lease interval',async()=>{
  const repo=makeRepository();const hold=deferred();
  const running=worker(repo,async()=>{await hold.promise;return coupon;},5).runOne(request);
  await new Promise(resolve=>setTimeout(resolve,45));
  hold.release();
  assert.equal((await running).status,'ready');
  assert.ok(repo.stats.renewals>=2);
});

test('a stale worker cannot publish after lease takeover on a new worker',async()=>{
  const repo=makeRepository();const hold=deferred();
  const firstRun=worker(repo,async()=>{await hold.promise;return coupon;}).runOne(request);
  await new Promise(resolve=>setImmediate(resolve));
  repo.expire();
  assert.equal((await worker(repo,async()=>coupon).runOne(request)).status,'ready');
  hold.release();
  assert.equal((await firstRun).status,'superseded');
  assert.equal(repo.stats.completions,1);
  assert.deepEqual(repo.saved.events,coupon.events);
});

test('withdrawn consent makes completion fail closed',async()=>{
  const repo=makeRepository();const hold=deferred();
  const run=worker(repo,async()=>{await hold.promise;return coupon;}).runOne(request);
  await new Promise(resolve=>setImmediate(resolve));
  repo.disable();hold.release();
  assert.equal((await run).status,'superseded');
  assert.equal(repo.stats.completions,0);
  assert.equal(repo.saved,null);
});

test('expired fifth attempt is marked unavailable on the next scheduled batch',async()=>{
  const pool=sqlPool([{rowCount:1}]);
  const repo=new LearningRepository(pool);
  assert.equal(await repo.finalizeExpiredAutoCouponRuns(),1);
  assert.match(pool.calls[0].sql,/status='processing' AND attempts >= 5/);
  assert.match(pool.calls[0].sql,/status='unavailable'/);
  assert.match(pool.calls[0].sql,/lease_token=NULL, lease_expires_at=NULL/);
});

test('incompatible unfenced repositories never run a generator',async()=>{
  let calls=0;const repo={async initialize(){},
    async claimAutoCouponRun(){return {attempts:1};},
    async renewAutoCouponLease(){return true;}};
  const result=await worker(repo,async()=>{calls++;return coupon;}).runOne(request);
  assert.equal(result.status,'invalid_lease');assert.equal(calls,0);
});
