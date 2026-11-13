'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createPrivateNeonWorker,IDLE_SWEEP_MS}=require('../auto_coupon/private_neon_worker');
const {createHeadlessEngineHost}=require('../auto_coupon/official_headless_runner');

const TOKEN='t'.repeat(48);
const SECOND='q'.repeat(48);
const REVISION='ab12cd3';
const ENV={
  AUTO_COUPON_PRIVATE_NEON_WORKER_ENABLED:'true',
  AUTO_COUPON_HEADLESS_HOST_ENABLED:'true',
  AUTO_COUPON_HEADLESS_PRIVATE_RENDER_BIND:'true',
  AUTO_COUPON_HEADLESS_B47_TOKEN:SECOND,
  AUTO_COUPON_HEADLESS_REVISION:REVISION,
  DATABASE_URL:'postgresql://local-test/isolated_db',
};

test('B47 private runner worker stays off by default and fails closed',()=>{
  assert.equal(createPrivateNeonWorker({env:{}}),null);
  assert.throws(()=>createPrivateNeonWorker({env:{
    ...ENV,AUTO_COUPON_HEADLESS_B47_TOKEN:'bad',
  }}),/mandatory configuration/);
  assert.throws(()=>createPrivateNeonWorker({env:{
    ...ENV,DATABASE_URL:'',
  }}),/mandatory configuration/);
});

test('B47 runner idle sweep uses no coupon execution and stops cleanly',async()=>{
  let claims=0,closed=0,scheduled=0,lastInterval=0,scheduledFn;
  const worker=createPrivateNeonWorker({
    env:ENV,
    poolFactory:()=>({end:async()=>{closed++;}}),
    repositoryFactory:()=>({
      async initialize(){},
      async claimOnDemandCoupon(){claims++;return null;},
    }),
    timerFn:(fn,interval)=>{
      scheduled++;scheduledFn=fn;lastInterval=interval;
      return {unref(){}};
    },
    clearFn:()=>{},
    fetchImpl:async()=>{throw Error('No remote request expected without a queued job');},
  });
  assert.equal(worker.ready,false);
  worker.start();
  for(let i=0;i<30 && !scheduled;i++)await new Promise(r=>setTimeout(r,2));
  assert.equal(worker.ready,true);
  assert.equal(claims,1);
  assert.equal(lastInterval,IDLE_SWEEP_MS);
  assert.equal(scheduled,1);
  assert.equal((await worker.tick()).status,'idle');
  assert.equal(claims,2);
  assert.equal(typeof scheduledFn,'function');
  await worker.stop();
  assert.equal(worker.ready,false);
  assert.equal(closed,1);
  assert.equal((await worker.tick()).status,'disabled');
});

test('B47 runner wake accepts only secondary credential and starts no synthetic task',async()=>{
  let cycles=0;
  const fakeWorker={ready:true,tick:async()=>{cycles++;return {status:'idle'};}};
  const server=createHeadlessEngineHost({
    token:TOKEN,additionalToken:SECOND,revision:REVISION,
    onDemandWorker:fakeWorker,
    now:()=>new Date('2026-11-13T10:00:00Z'),
    execute:async()=>{throw Error('Must never start headless generation in wake test');},
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const url='http://127.0.0.1:'+server.address().port;
  const invoke=(secret,method,path,body)=>fetch(url+path,{
    method,headers:{Authorization:'Bearer '+secret},
    ...(body?{body}:{}),
  });
  try {
    assert.equal((await invoke('x'.repeat(48),'POST','/coupon/on-demand/wake')).status,401);
    assert.equal((await invoke(TOKEN,'POST','/coupon/on-demand/wake')).status,401);
    assert.equal((await invoke(SECOND,'POST','/coupon/on-demand/wake','unknown')).status,400);
    const response=await invoke(SECOND,'POST','/coupon/on-demand/wake');
    assert.equal(response.status,202);
    assert.equal((await response.json()).workerNotified,true);
    assert.equal(cycles,1);
    const probe=await invoke(SECOND,'GET','/coupon/health');
    assert.equal((await probe.json()).workerReady,true);
  }finally{
    await new Promise(resolve=>server.close(resolve));
  }
});
