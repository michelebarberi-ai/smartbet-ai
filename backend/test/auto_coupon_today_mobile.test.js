'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {LearningService} = require('../learning/learning_service');
const {registerLearningRoutes} = require('../learning/learning_routes');

const token = 'z'.repeat(43);
const clientId = '11111111-1111-4111-8111-111111111111';
const env={LEARNING_SERVER_ENABLED:'true', LEARNING_MOBILE_INGEST_ENABLED:'true',
  AUTO_COUPON_PREFERENCES_ENABLED:'true', DATABASE_URL:'postgres://example.invalid/x',
  LEARNING_ADMIN_TOKEN:'a'.repeat(40), LEARNING_SUBJECT_SALT:'b'.repeat(40)};
const now = new Date('2026-11-09T07:45:00Z');
function appAndStorage(){
  const routes=new Map(); const storage=new Map();
  const repo={async initialize(){},
    async findValidClient(h){return h===crypto.createHash('sha256').update(token).digest('hex')?clientId:null;},
    async readAutoCouponDay({subjectHash,dayKey}){return storage.get(`${subjectHash}/${dayKey}`)||null;},
  };
  const service=new LearningService({repository:repo,subjectSalt:env.LEARNING_SUBJECT_SALT,now:()=>now});
  const app={get(path,...h){routes.set('GET '+path,h);},post(path,...h){routes.set('POST '+path,h);}};
  registerLearningRoutes(app,{env,learningService:service});
  return {routes, storage, service};
}
async function call(handlers, authorization=`Bearer ${token}`){
  const req={get(key){return key==='authorization'?authorization:null;}};
  const res={code:200, data:null, status(code){this.code=code;return this;},
    set(){return this;},json(obj){this.data=obj;return this;}};
  await handlers[0](req,res,()=>handlers[1](req,res));return res;
}
const key = 'GET /learning/v1/mobile/auto-coupon/today';

test('today endpoint only returns saved current-day result for authenticated device',async()=>{
  const {routes,storage}=appAndStorage();
  const handlers=routes.get(key);
  const empty=await call(handlers);
  assert.equal(empty.code,200);assert.equal(empty.data.status,'not_ready');
  assert.equal(empty.data.coupon,null);
  assert.equal(empty.data.dayKey,'2026-11-09');
  const h=crypto.createHmac('sha256',env.LEARNING_SUBJECT_SALT).update(clientId).digest('hex');
  storage.set(`${h}/2026-11-09`,{status:'ready',coupon:{events:[{fixtureId:9}]},generatedAt:now});
  const ready=await call(handlers);
  assert.equal(ready.data.status,'ready');assert.equal(ready.data.coupon.events[0].fixtureId,9);
  assert.equal(ready.data.generationActive,false);assert.equal(ready.data.pushActive,false);
  assert.equal((await call(handlers,'Bearer '+'a'.repeat(43))).code,401);
  assert.equal((await call(handlers,null)).code,401);
});

test('read-only endpoint does not expose incomplete coupon and checks feature flag',async()=>{
  const {routes,storage}=appAndStorage();
  const h=crypto.createHmac('sha256',env.LEARNING_SUBJECT_SALT).update(clientId).digest('hex');
  storage.set(`${h}/2026-11-09`,{status:'retry',coupon:{events:[{fixtureId:1}]}});
  const response=await call(routes.get(key));
  assert.equal(response.data.status,'retry');assert.equal(response.data.coupon,null);
  const noFlagRoutes=new Map();
  const app={get(p,...handlers){noFlagRoutes.set('GET '+p,handlers);},post(){}};
  registerLearningRoutes(app,{env:{...env,AUTO_COUPON_PREFERENCES_ENABLED:'false'},
    learningService:new LearningService({repository:{async initialize(){},
      async findValidClient(){return clientId;}},subjectSalt:env.LEARNING_SUBJECT_SALT})});
  const disabled=await call(noFlagRoutes.get(key));
  assert.equal(disabled.code,503);
});
