'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {registerLearningRoutes} = require('../learning/learning_routes');
const {LearningService} = require('../learning/learning_service');
const {ROUTE, normalizeBatchRequest} = require('../auto_coupon/worker_route');

const TOKEN = 'w'.repeat(48);
const HASH = '1'.repeat(64);
const now = new Date('2026-11-09T08:15:00Z');
const preferences = {requested:true,hour:8,minute:0,events:3,
  minimumMarketProbability:65,market:'MULTI',notifyChanges:true};
const coupon = {events:[1,2,3].map(fixtureId => ({fixtureId,market:'1X2',
  marketProbability:75,kickoffAt:'2026-11-09T18:00:00Z',odds:1.8}))};
const configuredEnv = {LEARNING_SERVER_ENABLED:'true',DATABASE_URL:'postgres://localhost/unused',
  LEARNING_ADMIN_TOKEN:'a'.repeat(40),LEARNING_SUBJECT_SALT:'b'.repeat(40),
  LEARNING_MOBILE_INGEST_ENABLED:'true', AUTO_COUPON_PREFERENCES_ENABLED:'true',
  AUTO_COUPON_WORKER_ENABLED:'true',AUTO_COUPON_WORKER_TOKEN:TOKEN};

function fakeApp() {
  const routes = new Map();
  return {routes,get(path,...handlers){routes.set(`GET ${path}`,handlers);},
    post(path,...handlers){routes.set(`POST ${path}`,handlers);}};
}
function fakeRes() {
  return {code:200,payload:null,headers:{},status(code){this.code=code;return this;},
    set(k,v){this.headers[k]=v;return this;},json(v){this.payload=v;return this;}};
}
function setup({env = configuredEnv,official = async()=>coupon,repository}={}) {
  const repo = repository || {calls:0,async initialize(){this.calls++;},
    async listAutoCouponSubscribers(){return [{subjectHash:HASH,preferences}];},
    async renewAutoCouponLease(){return true;},async claimAutoCouponRun(){return {attempts:1, leaseToken: '11111111-1111-4111-8111-111111111111'};},
    async finishAutoCouponRun(){return true;}};
  const service = new LearningService({repository:repo,subjectSalt:env.LEARNING_SUBJECT_SALT,
    now:()=>now});
  const app = fakeApp();
  registerLearningRoutes(app,{env,learningService:service,
    now:()=>now,generateOfficialCoupon:official});
  return {app,repo};
}
async function invoke(app,{token = TOKEN,body = {}}={}) {
  const res = fakeRes();
  await app.routes.get(`POST ${ROUTE}`)[0]({body,
    get(header){return header==='x-goalvdline-worker-token'?token:null;}},res);
  return res;
}

test('server flags fail closed and do not touch repository', async()=>{
  for (const env of [
    {...configuredEnv,AUTO_COUPON_WORKER_ENABLED:'false'},
    {...configuredEnv,AUTO_COUPON_PREFERENCES_ENABLED:'false'},
    {...configuredEnv,LEARNING_MOBILE_INGEST_ENABLED:'false'},
    {...configuredEnv,AUTO_COUPON_WORKER_TOKEN:'too short'},
  ]) {
    const {app,repo}=setup({env});
    const response=await invoke(app);
    assert.equal(response.code,503);assert.equal(repo.calls,0);
    const status=fakeRes();app.routes.get('GET /learning/v1/status')[0]({},status);
    assert.equal(status.payload.autoCouponWorkerReady,false);
    assert.equal(status.payload.autoCouponGenerationEnabled,false);
  }
});

test('missing official generator cannot start worker even with flags',async()=>{
  const {app,repo}=setup({official:null});
  assert.equal((await invoke(app)).code,503);assert.equal(repo.calls,0);
});

test('invalid worker token and admin token are rejected without DB work',async()=>{
  const {app,repo}=setup();
  for (const token of [null,'x'.repeat(48),configuredEnv.LEARNING_ADMIN_TOKEN,'']) {
    const response=await invoke(app,{token});
    assert.equal(response.code,401);
  }
  assert.equal(repo.calls,0);
});

test('invalid batch body rejected without database access',async()=>{
  const {app,repo}=setup();
  for(const body of [null,[],{limit:0},{limit:26},{limit:1.2},
    {afterSubjectHash:'non-hash'}, {clientId:'spoof'}, {limit:10,unknown:1}]){
    assert.equal((await invoke(app,{body})).code,400);
  }
  assert.equal(repo.calls,0);
});

test('valid worker creates only verified official coupon and returns no PII',async()=>{
  const {app,repo}=setup();
  const response=await invoke(app,{body:{limit:1}});
  assert.equal(response.code,200);
  assert.equal(response.payload.success,true);
  assert.equal(response.payload.results.ready,1);
  assert.equal(response.payload.checked,1);
  assert.equal(repo.calls>0,true);
  assert.equal(JSON.stringify(response.payload).includes('odds'),false);
  const status=fakeRes();app.routes.get('GET /learning/v1/status')[0]({},status);
  assert.equal(status.payload.autoCouponWorkerReady,true);
  assert.equal(status.payload.autoCouponGenerationEnabled,false);
  assert.equal(status.payload.autoCouponPushEnabled,false);
});

test('low-probability coupon never marked ready',async()=>{
  const repo={async initialize(){},async listAutoCouponSubscribers(){return [{subjectHash:HASH,preferences}]},
    async renewAutoCouponLease(){return true;},async claimAutoCouponRun(){return {attempts:1, leaseToken: '11111111-1111-4111-8111-111111111111'}},
    async finishAutoCouponRun(args){this.saved=args;return true;}};
  const {app}=setup({repository:repo,official:async()=>({...coupon,events:coupon.events.map(
    (event,i)=>({...event,marketProbability:i===0?12:75}))})});
  const response=await invoke(app);
  assert.equal(response.payload.results.retry,1);
  assert.equal(repo.saved.coupon ?? null,null);
});

test('database error is reported without leaking internal details',async()=>{
  const {app}=setup({repository:{async initialize(){throw Error('DATABASE_URL=secret')}}});
  const old=console.error;console.error=()=>{};
  try {
    const response=await invoke(app);
    assert.equal(response.code,503);
    assert.equal(JSON.stringify(response.payload).includes('secret'),false);
  } finally {console.error=old;}
});

test('batch request has strict safe bounds',()=>{
  assert.deepEqual(normalizeBatchRequest({}),{limit:20,afterSubjectHash:null});
  assert.deepEqual(normalizeBatchRequest({limit:25,afterSubjectHash:HASH}),
    {limit:25,afterSubjectHash:HASH});
  assert.equal(normalizeBatchRequest({limit:26}),null);
});
