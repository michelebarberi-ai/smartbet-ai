'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs/promises');
const {createHeadlessEngineHost} = require('../auto_coupon/official_headless_runner');
const {createDurableHeadlessJobStore} = require('../auto_coupon/durable_headless_job_store');
const {PROTOCOL} = require('../auto_coupon/official_engine_client');

const TOKEN = 'P'.repeat(48);
const REVISION = 'eac3323';
const now = new Date('2026-11-09T08:15:00Z');
const late = new Date('2026-11-09T08:17:00Z');
const preferences = {requested:true,hour:8,minute:0,events:3,
  minimumMarketProbability:65,market:'MULTI',notifyChanges:true};
const request = {protocol:PROTOCOL,dayKey:'2026-11-09',
  generatedAfter:now.toISOString(),preferences};
const coupon = {events:[1,2,3].map(fixtureId=>({fixtureId,
  market:'OVER 1.5',marketProbability:80,
  kickoffAt:'2026-11-09T18:00:00.000Z',odds:1.4}))};

async function start(dir, execute, clock=()=>now) {
  const server = createHeadlessEngineHost({token:TOKEN,revision:REVISION,execute,
    now:clock,jobStore:createDurableHeadlessJobStore(dir)});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  return {base,close:()=>new Promise(resolve=>server.close(resolve))};
}
async function call(base,method,url,body) {
  return fetch(base+url,{method,headers:{Authorization:`Bearer ${TOKEN}`,
    'Content-Type':'application/json'}, ...(body?{body:JSON.stringify(body)}:{})});
}
async function poll(base,id,expected) {
  for (let i=0;i<80;i++) {
    const response=await call(base,'GET',`/coupon/jobs/${id}`);
    if(response.status===expected)return response;
    await new Promise(resolve=>setTimeout(resolve,5));
  }
  assert.fail(`Job never reached status ${expected}`);
}

async function withDir(run) {
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'b45-journal-test-'));
  try {await run(dir);}finally{await fs.rm(dir,{recursive:true,force:true});}
}

test('verified ready job remains available after host restart',async()=>withDir(async dir=>{
  let calls=0;
  const execute=async()=>{calls++;return {protocol:PROTOCOL,
    officialEngine:true,revision:REVISION,status:'ready',coupon};};
  const first=await start(dir,execute);
  let id;
  try {
    const response=await call(first.base,'POST','/coupon/generate',request);
    assert.equal(response.status,202);
    id=(await response.json()).jobId;
    assert.equal((await poll(first.base,id,200)).status,200);
  } finally {await first.close();}
  const second=await start(dir,execute);
  try {
    assert.equal((await call(second.base,'GET',`/coupon/jobs/${id}`)).status,200);
    const same=await call(second.base,'POST','/coupon/generate',{
      ...request,generatedAfter:new Date(now.getTime()+1000).toISOString(),
    });
    assert.equal((await same.json()).jobId,id);
    assert.equal(calls,1);
    const files=await fs.readdir(dir);
    assert.equal(files.filter(n=>n.endsWith('.json')).length,1);
    const record=await fs.readFile(path.join(dir,`${id}.json`),'utf8');
    assert.equal(record.includes(TOKEN),false);
  } finally {await second.close();}
}));

test('unfinished journal is failed closed on restart and may be retried',async()=>withDir(async dir=>{
  const store=createDurableHeadlessJobStore(dir);
  const id='f'.repeat(32);
  await store.save(id,{createdAt:now,signature:'a'.repeat(64),request,
    status:'running',result:null});
  const runner=await start(dir,async()=>({protocol:PROTOCOL,
    officialEngine:true,revision:REVISION,status:'ready',coupon}));
  try {
    assert.equal((await call(runner.base,'GET',`/coupon/jobs/${id}`)).status,503);
    const restored=await store.load();
    assert.equal(restored.get(id).status,'failed');
    const fresh=await call(runner.base,'POST','/coupon/generate',request);
    assert.equal(fresh.status,202);
    const freshId=(await fresh.json()).jobId;
    assert.notEqual(freshId,id);
    assert.equal((await poll(runner.base,freshId,200)).status,200);
  } finally {await runner.close();}
}));

test('finished coupon is not served after kickoff',async()=>withDir(async dir=>{
  let current=now;
  const nearKickoffCoupon={events:coupon.events.map(event=>({
    ...event,kickoffAt:'2026-11-09T08:16:00.000Z',
  }))};
  const runner=await start(dir,async()=>({protocol:PROTOCOL,
    officialEngine:true,revision:REVISION,status:'ready',
    coupon:nearKickoffCoupon}),()=>current);
  try {
    const response=await call(runner.base,'POST','/coupon/generate',request);
    const id=(await response.json()).jobId;
    await poll(runner.base,id,200);
    current=late;
    assert.equal((await call(runner.base,'GET',`/coupon/jobs/${id}`)).status,503);
  } finally {await runner.close();}
}));

test('concurrent POSTs cannot launch two Flutter jobs',async()=>withDir(async dir=>{
  let release;
  let calls=0;
  const waiting=new Promise(resolve=>{release=resolve;});
  const runner=await start(dir,async()=>{calls++;await waiting;
    return {protocol:PROTOCOL,officialEngine:true,revision:REVISION,
      status:'ready',coupon};});
  try {
    const results=await Promise.all([
      call(runner.base,'POST','/coupon/generate',request),
      call(runner.base,'POST','/coupon/generate',request),
    ]);
    const statuses=results.map(r=>r.status);
    assert.ok(statuses.every(x=>x===202||x===429));
    assert.equal(calls,1);
    release();
    const id=(await results.find(r=>r.status===202).json()).jobId;
    await poll(runner.base,id,200);
  } finally {release();await runner.close();}
}));

test('corrupt persistent journal fails closed without invoking Flutter',async()=>withDir(async dir=>{
  await fs.writeFile(path.join(dir,`${'1'.repeat(32)}.json`),'{broken JSON',
    {mode:0o600});
  let called=0;
  const runner=await start(dir,async()=>{called++;return {
    protocol:PROTOCOL,officialEngine:true,revision:REVISION,
    status:'ready',coupon};});
  try {
    const response=await call(runner.base,'POST','/coupon/generate',request);
    assert.equal(response.status,503);
    assert.equal((await response.json()).error,'job_store_unavailable');
    assert.equal(called,0);
  } finally {await runner.close();}
}));
