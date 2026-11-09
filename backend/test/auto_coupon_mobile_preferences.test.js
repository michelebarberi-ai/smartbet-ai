'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {registerLearningRoutes} = require('../learning/learning_routes');
const {LearningService} = require('../learning/learning_service');

const token = 'a'.repeat(43);
const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
const now = new Date('2026-11-09T10:00:00Z');
const env = {LEARNING_SERVER_ENABLED: 'true', LEARNING_MOBILE_INGEST_ENABLED: 'true',
  AUTO_COUPON_PREFERENCES_ENABLED: 'true', DATABASE_URL: 'postgres://example.invalid/db',
  LEARNING_ADMIN_TOKEN: 'b'.repeat(40), LEARNING_SUBJECT_SALT: 'c'.repeat(40)};
const preferences = {requested:true, hour:8, minute:15, events:4,
  minimumMarketProbability:65, market:'MULTI', notifyChanges:true};
function fakeApp() {
  const routes = new Map();
  return {routes, get(p,...handlers){routes.set(`GET ${p}`, handlers);},
    post(p,...handlers){routes.set(`POST ${p}`, handlers);}};
}
function res() {return {code:200,payload:null,headers:{}, status(c){this.code=c; return this;},
  set(k,v){this.headers[k]=v;return this;}, json(data){this.payload=data;return this;}};}
function req(body, auth = `Bearer ${token}`) {
  return {body, get(key){return key.toLowerCase()==='authorization'?auth:null;}};
}
async function invoke(handlers, request) {
  const response = res();
  const next = async()=>handlers[1](request,response);
  await handlers[0](request,response,next);
  return response;
}
function setup(environment = env) {
  const clients = new Map([[tokenHash, '11111111-1111-4111-8111-111111111111']]);
  const saved = new Map();
  const repository = {async initialize(){}, async findValidClient(hash){return clients.get(hash)||null;},
    async upsertAutoCouponPreferences({subjectHash,preferences: p}){saved.set(subjectHash,p);},
    async readAutoCouponPreferences(subjectHash){return saved.get(subjectHash)||null;},
  };
  const service = new LearningService({repository,subjectSalt:environment.LEARNING_SUBJECT_SALT,
    now:()=>now, fetchFixture:async()=>{throw Error('No fixtures may be fetched')}});
  const app = fakeApp(); registerLearningRoutes(app,{env:environment,learningService:service});
  return {app,saved,clients};
}
const post = 'POST /learning/v1/mobile/auto-coupon/preferences';
const get = 'GET /learning/v1/mobile/auto-coupon/preferences';

test('flag disabled by default; no preference can be stored',async()=>{
  const {app,saved}=setup({...env,AUTO_COUPON_PREFERENCES_ENABLED:'false'});
  const status = res(); app.routes.get('GET /learning/v1/status')[0]({},status);
  assert.equal(status.payload.autoCouponPreferencesEnabled,false);
  assert.equal(status.payload.autoCouponGenerationEnabled,false);
  assert.equal(status.payload.autoCouponPushEnabled,false);
  const reply=await invoke(app.routes.get(post),req({preferences}));
  assert.equal(reply.code,503); assert.equal(saved.size,0);
});

test('mobile token required; invalid and unknown tokens rejected',async()=>{
  const {app,saved}=setup();
  assert.equal((await invoke(app.routes.get(post),req({preferences},null))).code,401);
  assert.equal((await invoke(app.routes.get(post),req({preferences},'Bearer '+ 'z'.repeat(43)))).code,401);
  assert.equal(saved.size,0);
});

test('accepted preferences saved only for hashed authenticated client; no automation',async()=>{
  const {app,saved}=setup();
  const reply=await invoke(app.routes.get(post),req({preferences}));
  assert.equal(reply.code,200); assert.equal(reply.payload.saved,true);
  assert.equal(reply.payload.generationActive,false);
  assert.equal(reply.payload.pushActive,false);
  assert.equal(saved.size,1);
  const hash=crypto.createHmac('sha256',env.LEARNING_SUBJECT_SALT)
    .update('11111111-1111-4111-8111-111111111111').digest('hex');
  assert.deepEqual(saved.get(hash),preferences);
  const fetch=await invoke(app.routes.get(get),req());
  assert.equal(fetch.code,200); assert.deepEqual(fetch.payload.preferences,preferences);
});

test('invalid preferences and unexpected fields never persisted',async()=>{
  const {app,saved}=setup();
  for (const body of [{preferences:{...preferences,events:16}},
    {preferences:{...preferences,minimumMarketProbability:10}},
    {preferences,clientId:'spoof'}, {}, {preferences:'invalid'}]) {
    const reply=await invoke(app.routes.get(post),req(body));
    assert.equal(reply.code,400);
  }
  assert.equal(saved.size,0);
});

test('additional harmless properties are not stored; disabling is persisted',async()=>{
  const {app,saved}=setup();
  const reply=await invoke(app.routes.get(post),req({preferences:{...preferences,
    requested:false,unexpectedPrivateField:'should never store'}}));
  assert.equal(reply.code,200);
  const stored=[...saved.values()][0];
  assert.equal(stored.requested,false);
  assert.equal(Object.hasOwn(stored,'unexpectedPrivateField'),false);
});

test('revoke of mobile credential also removes any saved preferences',async()=>{
  const removed = [];
  const repository = {async initialize(){}, async revokeClient(){return true;},
    async deleteAutoCouponPreferences(hash){removed.push(hash);}};
  const svc = new LearningService({repository, subjectSalt:env.LEARNING_SUBJECT_SALT,
    now:()=>now});
  const clientId='11111111-1111-4111-8111-111111111111';
  const result=await svc.revokeMobileClient(clientId);
  assert.equal(result.body.revoked,true);
  assert.equal(removed.length,1);
  assert.equal(removed[0],crypto.createHmac('sha256',env.LEARNING_SUBJECT_SALT)
    .update(clientId).digest('hex'));
});
