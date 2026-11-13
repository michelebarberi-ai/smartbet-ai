'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createOnDemandScheduler}=require('../auto_coupon/on_demand_scheduler');

test('B47 scheduler fails closed with invalid configuration',()=>{
  assert.throws(()=>createOnDemandScheduler(),TypeError);
  assert.throws(()=>createOnDemandScheduler({runOne:async()=>{},intervalMs:1000}),TypeError);
  assert.throws(()=>createOnDemandScheduler({runOne:async()=>{},intervalMs:300001}),TypeError);
});

test('B47 scheduler has no timer until explicit start and no overlap',async()=>{
  let clockTick,created=0,cleared=0,started=0;
  let release;
  const hold=new Promise(resolve=>{release=resolve;});
  const s=createOnDemandScheduler({
    runOne:async()=>{started++;await hold;return {status:'ready'};},
    intervalMs:60000,
    setIntervalFn:fn=>{created++;clockTick=fn;return{unref(){};};},
    clearIntervalFn:()=>{cleared++;},
  });
  assert.equal(created,0);
  s.start();
  assert.equal(created,1);
  const first=s.tick();
  assert.equal((await s.tick()).status,'busy');
  clockTick();
  assert.equal(started,1);
  release();
  assert.equal((await first).status,'ready');
  await s.stop();
  assert.equal(cleared,1);
  assert.equal((await s.tick()).status,'stopped');
});

test('B47 scheduler errors do not leak provider details',async()=>{
  const errors=[];
  const s=createOnDemandScheduler({runOne:async()=>{throw Error('secret');},
    onError:reason=>errors.push(reason)});
  assert.equal((await s.tick()).status,'error');
  assert.deepEqual(errors,['worker_cycle_failed']);
  await s.stop();
});
