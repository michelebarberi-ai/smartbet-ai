'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {encryptDeviceToken} = require('../auto_coupon/device_registration');
const {ROUTE, normalizePushBatch, futureCoupon, AutoCouponPushDispatcher,
  registerAutoCouponPushDispatchRoute} = require('../auto_coupon/push_dispatch');
const {registerLearningRoutes} = require('../learning/learning_routes');
const {LearningService} = require('../learning/learning_service');

const HASH = 'a'.repeat(64);
const HASH2 = 'b'.repeat(64);
const TOKEN = 'w'.repeat(48);
const KEY = crypto.randomBytes(32).toString('hex');
const DEVICE = 'ab'.repeat(32);
const TODAY = new Date('2026-11-09T08:15:00.000Z');
const DAY = '2026-11-09';
const coupon = {events: [1, 2, 3].map(fixtureId => ({fixtureId,
  market: '1X2', marketProbability: 76, kickoffAt: '2026-11-09T19:00:00.000Z'}))};
const env = {AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY: KEY, APNS_ENVIRONMENT: 'production'};
const encrypted = encryptDeviceToken({deviceToken:DEVICE, subjectHash:HASH,
  environment:'production', keyHex:KEY});

function appFake() {const routes = new Map();return {routes,
  post(path,...handlers){routes.set(`POST ${path}`,handlers);},
  get(path,...handlers){routes.set(`GET ${path}`,handlers);}};}
function response() {return {statusCode:200,body:null,headers:{},
  status(n){this.statusCode=n;return this;},
  json(v){this.body=v;return this;},set(k,v){this.headers[k]=v;return this;}};}
async function request(app,{token=TOKEN,body={}}={}) {
  const res=response();
  await app.routes.get(`POST ${ROUTE}`)[0]({body,
    get(name){return name==='x-goalvdline-worker-token'?token:null;}},res);
  return res;
}
function fakeRepo({subjects=[HASH],devices=true,previous=null,readyCoupon=coupon}={}) {
  const state = new Map(previous ? [[HASH,{...previous}]] : []);
  const calls={initialized:0,sent:0,removed:0};
  const repo={calls,state,
    async initialize(){calls.initialized++;},
    async listPendingAutoCouponPushes({dayKey,limit,afterSubjectHash}){
      assert.equal(dayKey,DAY);
      return subjects.filter(x=>(!afterSubjectHash || x>afterSubjectHash) &&
        !['sent','unavailable','unregistered'].includes(state.get(x)?.status))
        .slice(0,limit).map(subjectHash=>({subjectHash}));
    },
    async claimAutoCouponPush({subjectHash}){
      const old=state.get(subjectHash);
      if (old && old.status!=='retry') return null;
      const attempts=(old?.attempts||0)+1;
      state.set(subjectHash,{status:'processing',attempts});return {attempts};
    },
    async readAutoCouponDay(){return {status:'ready',coupon:readyCoupon};},
    async readAutoCouponPushDevice(subjectHash){return devices?{
      ...encryptDeviceToken({deviceToken:DEVICE,subjectHash,environment:'production',keyHex:KEY}),
      environment:'production'}:null;},
    async deleteAutoCouponPushDeviceIfMatch(){calls.removed++;},
    async finishAutoCouponPush({subjectHash,attempts,outcome,reason}){
      assert.equal(state.get(subjectHash)?.attempts,attempts);
      state.set(subjectHash,{status:outcome==='retry' && attempts>=5?'unavailable':outcome,
        attempts,reason});return true;
    },
  };return repo;
}
function makeDispatcher(repository,{now=()=>TODAY,send=async()=>({status:'accepted_by_apns'}),
  options=env}={}) {
  return new AutoCouponPushDispatcher({repository,env:options,now,send});
}

test('push worker is disabled unless explicitly enabled; no database access',async()=>{
  const repository=fakeRepo();const app=appFake();
  registerAutoCouponPushDispatchRoute(app,{getRepository:()=>repository,workerToken:TOKEN,
    env,now:()=>TODAY});
  const res=await request(app);
  assert.equal(res.statusCode,503);assert.equal(repository.calls.initialized,0);
});

test('worker key, admin key and malformed batches are rejected before DB access',async()=>{
  const repository=fakeRepo();const app=appFake();
  registerAutoCouponPushDispatchRoute(app,{enabled:true,workerToken:TOKEN,
    getRepository:()=>repository,env,now:()=>TODAY});
  for (const token of [null,'q'.repeat(48),'a'.repeat(40)]) {
    assert.equal((await request(app,{token})).statusCode,401);
  }
  for (const body of [null,[],{limit:0},{limit:26},{limit:3.1},
    {clientId:HASH},{afterSubjectHash:'invalid'}]) {
    assert.equal((await request(app,{body})).statusCode,400);
  }
  assert.equal(repository.calls.initialized,0);
});

test('valid endpoint only returns counts and cursor, never APNs token',async()=>{
  const repository=fakeRepo();const app=appFake();
  const send=async ({deviceToken})=>{assert.equal(deviceToken,DEVICE);
    return {status:'accepted_by_apns'};};
  registerAutoCouponPushDispatchRoute(app,{enabled:true,workerToken:TOKEN,
    getRepository:()=>repository,env,now:()=>TODAY,send});
  const res=await request(app,{body:{limit:1}});
  assert.equal(res.statusCode,200);
  assert.equal(res.body.results.sent,1);
  assert.equal(res.body.nextCursor,HASH);
  assert.equal(JSON.stringify(res.body).includes(DEVICE),false);
  assert.equal(res.headers['Cache-Control'],'no-store');
});

test('never sends again after successful APNs acceptance',async()=>{
  const repo=fakeRepo();let sent=0;
  const dispatch=makeDispatcher(repo,{send:async()=>{sent++;return {status:'accepted_by_apns'};}});
  assert.equal((await dispatch.runBatch()).results.sent,1);
  assert.equal((await dispatch.runBatch()).results.sent,0);
  assert.equal(sent,1);
});

test('already claimed work is not sent twice on concurrent worker calls',async()=>{
  const repo=fakeRepo();let sent=0;
  const dispatch=makeDispatcher(repo,{send:async()=>{sent++;
    await new Promise(resolve=>setImmediate(resolve));return {status:'accepted_by_apns'};}});
  const [a,b]=await Promise.all([dispatch.runBatch(),dispatch.runBatch()]);
  assert.equal(a.results.sent+b.results.sent,1);
  assert.equal(sent,1);
});

test('unregistered token removes only matching ciphertext',async()=>{
  const repo=fakeRepo();
  const dispatch=makeDispatcher(repo,{send:async()=>({status:'unregistered_device'})});
  const result=await dispatch.runBatch();
  assert.equal(result.results.unregistered,1);
  assert.equal(repo.calls.removed,1);
});

test('network problems retry; after fifth attempt dispatch stops',async()=>{
  const repo=fakeRepo();
  const dispatch=makeDispatcher(repo,{send:async()=>({status:'transport_error'})});
  for(let i=1;i<=5;i++){
    const result=await dispatch.runBatch();
    assert.equal(result.results[i===5?'unavailable':'retry'],1);
  }
  assert.equal((await dispatch.runBatch()).checked,0);
  assert.equal(repo.state.get(HASH).attempts,5);
});

test('missing device or invalid/stale coupon never calls Apple',async()=>{
  for (const opts of [{devices:false},{readyCoupon:{events:[{
    fixtureId:1,market:'1X2',marketProbability:80,kickoffAt:'2026-11-09T07:00:00Z'}]}}]) {
    const repo=fakeRepo(opts);
    const dispatch=makeDispatcher(repo,{send:async()=>{throw Error('must not call APNs');}});
    const result=await dispatch.runBatch();
    assert.equal(result.results.unavailable,1);
  }
});

test('wrong APNs environment and corrupt encryption never transmit tokens',async()=>{
  const repo=fakeRepo();
  const dispatch=makeDispatcher(repo,{options:{...env,APNS_ENVIRONMENT:'sandbox'},
    send:async()=>{throw Error('never send');}});
  assert.equal((await dispatch.runBatch()).results.retry,1);
  const repo2=fakeRepo();
  const dispatch2=makeDispatcher(repo2,{options:{...env,AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY:'0'.repeat(64)},
    send:async()=>{throw Error('never send');}});
  assert.equal((await dispatch2.runBatch()).results.retry,1);
});

test('cursor and batch size validation is strict',()=>{
  assert.deepEqual(normalizePushBatch({}),{limit:20,afterSubjectHash:null});
  assert.deepEqual(normalizePushBatch({limit:25,afterSubjectHash:HASH2}),
    {limit:25,afterSubjectHash:HASH2});
  for (const body of [{limit:-1},{limit:26},{limit:NaN},{foo:123},null,[]])
    assert.equal(normalizePushBatch(body),null);
});

test('invalid coupon including duplicates and wrong local day is rejected',()=>{
  assert.equal(futureCoupon(coupon,DAY,TODAY),true);
  assert.equal(futureCoupon({events:[coupon.events[0],coupon.events[0],coupon.events[2]]},DAY,TODAY),false);
  assert.equal(futureCoupon({...coupon,events:coupon.events.map(x=>({...x,kickoffAt:'2026-11-10T19:00:00Z'}))},DAY,TODAY),false);
});

test('learning route exposes disabled push dispatch status unless all gates are set',()=>{
  const app=appFake();
  const base={LEARNING_SERVER_ENABLED:'true',DATABASE_URL:'postgres://test.invalid/db',
    LEARNING_ADMIN_TOKEN:'a'.repeat(40),LEARNING_SUBJECT_SALT:'b'.repeat(40),
    LEARNING_MOBILE_INGEST_ENABLED:'true',AUTO_COUPON_PREFERENCES_ENABLED:'true',
    AUTO_COUPON_WORKER_ENABLED:'true',AUTO_COUPON_WORKER_TOKEN:TOKEN};
  registerLearningRoutes(app,{env:base,generateOfficialCoupon:async()=>coupon,
    learningService:new LearningService({repository:fakeRepo(),subjectSalt:'b'.repeat(40)})});
  const res=response();app.routes.get('GET /learning/v1/status')[0]({},res);
  assert.equal(res.body.autoCouponPushDispatchReady,false);
  assert.equal(res.body.autoCouponPushEnabled,false);
});
