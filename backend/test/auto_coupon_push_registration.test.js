'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {registrationReady, encryptDeviceToken, decryptDeviceToken} =
  require('../auto_coupon/device_registration');
const {registerLearningRoutes} = require('../learning/learning_routes');
const {LearningService} = require('../learning/learning_service');
const {hashClientId} = require('../learning/learning_core');
const clientId = '11111111-1111-4111-8111-111111111111';
const token = 'a'.repeat(43);
const subjectSalt = 'c'.repeat(40);
const subjectHash = hashClientId(clientId, subjectSalt);
const key = crypto.randomBytes(32).toString('hex');
const apns = 'ab'.repeat(32);
const env = {LEARNING_SERVER_ENABLED: 'true', LEARNING_MOBILE_INGEST_ENABLED: 'true',
  AUTO_COUPON_PREFERENCES_ENABLED: 'true', AUTO_COUPON_PUSH_REGISTRATION_ENABLED: 'true',
  AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY: key, APNS_ENVIRONMENT: 'production',
  DATABASE_URL: 'postgres://not-used.invalid/db',
  LEARNING_ADMIN_TOKEN: 'b'.repeat(40), LEARNING_SUBJECT_SALT: subjectSalt};
const prefs = {requested: true, hour: 8, minute: 0, events: 4,
  minimumMarketProbability: 65, market: 'MULTI', notifyChanges: true};

function appFake() { const routes = new Map(); return {routes,
  get(name, ...handlers) {routes.set(`GET ${name}`, handlers);},
  post(name, ...handlers) {routes.set(`POST ${name}`, handlers);}}; }
function response() {return {code:200,payload:null,headers:{},status(c){this.code=c;return this;},
  set(k,v){this.headers[k]=v;return this;},json(p){this.payload=p;return this;}};}
function request(body, auth = `Bearer ${token}`) {return {body,
  get(k){return k.toLowerCase()==='authorization' ? auth : undefined;}};}
async function call(handlers, r) {const res = response();
  await handlers[0](r,res,async () => handlers[1](r,res));return res;}
function setup(overrides = {}, requested = true) {
  const saved = new Map(); const pushes = new Map();
  if (requested) saved.set(subjectHash, prefs);
  const repo = {async initialize(){},
    async findValidClient(hash){return hash === crypto.createHash('sha256').update(token).digest('hex') ? clientId : null;},
    async readAutoCouponPreferences(hash){return saved.get(hash) || null;},
    async upsertAutoCouponPreferences({subjectHash: hash, preferences}){saved.set(hash,preferences);},
    async upsertAutoCouponPushDevice(entry){pushes.set(entry.subjectHash,entry);},
    async deleteAutoCouponPushDevice(hash){pushes.delete(hash);},
  };
  const effectiveEnv = {...env,...overrides};
  const service = new LearningService({repository:repo, subjectSalt,
    now:()=>new Date('2026-11-09T12:00:00Z')});
  const app = appFake(); registerLearningRoutes(app,{env:effectiveEnv, learningService:service});
  return {app,saved,pushes,service};
}
const registerPath = 'POST /learning/v1/mobile/auto-coupon/push/register';
const unregisterPath = 'POST /learning/v1/mobile/auto-coupon/push/unregister';

test('registration is disabled by default, no database writes or permission implied', async () => {
  const {app,pushes} = setup({AUTO_COUPON_PUSH_REGISTRATION_ENABLED:'false'});
  const status = response(); app.routes.get('GET /learning/v1/status')[0]({},status);
  assert.equal(status.payload.autoCouponDeviceRegistrationEnabled,false);
  const res = await call(app.routes.get(registerPath),request({deviceToken:apns}));
  assert.equal(res.code,503);assert.equal(pushes.size,0);
  assert.equal(registrationReady({}),false);
  assert.equal(registrationReady(env),true);
  assert.equal(registrationReady({...env,AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY:'invalid'}),false);
});

test('mobile auth required and invalid registration body rejected',async()=>{
  const {app,pushes} = setup();
  assert.equal((await call(app.routes.get(registerPath),request({deviceToken:apns},'Bearer bad'))).code,401);
  for (const body of [{deviceToken:'bad'},{deviceToken:apns,clientId},{deviceToken:apns,env:'sandbox'},{}]) {
    const r=await call(app.routes.get(registerPath),request(body));assert.equal(r.code,400);
  }
  assert.equal(pushes.size,0);
});

test('requires synchronized daily schedule opt-in before registration',async()=>{
  const {app,pushes}=setup({},false);
  assert.equal((await call(app.routes.get(registerPath),request({deviceToken:apns}))).code,409);
  assert.equal(pushes.size,0);
});

test('encrypts APNs identifier for authenticated client only; no push is sent',async()=>{
  const {app,pushes}=setup();
  const result=await call(app.routes.get(registerPath),request({deviceToken:apns}));
  assert.equal(result.code,200);assert.equal(result.payload.registered,true);
  assert.equal(result.payload.pushActive,false);
  assert.equal(JSON.stringify(result.payload).includes(apns),false);
  assert.equal(pushes.size,1);
  const stored=pushes.get(subjectHash);
  assert.equal(stored.subjectHash,subjectHash);
  assert.equal(stored.environment,'production');
  assert.equal(JSON.stringify(stored).includes(apns),false);
  assert.equal(decryptDeviceToken({record:stored,subjectHash,keyHex:key}),apns);
  assert.equal(result.headers['Cache-Control'],'no-store');
});

test('tampering with ciphertext, environment or subject breaks authentication',()=>{
  const sealed=encryptDeviceToken({deviceToken:apns,subjectHash,environment:'production',keyHex:key});
  assert.throws(()=>decryptDeviceToken({record:{...sealed,environment:'sandbox'},subjectHash,keyHex:key}));
  const forged = {...sealed,ciphertext:Buffer.from('edited').toString('base64'),environment:'production'};
  assert.throws(()=>decryptDeviceToken({record:forged,subjectHash,keyHex:key}));
});

test('mobile unregister and preference opt-out erase device token',async()=>{
  const {app,pushes,service}=setup();
  await call(app.routes.get(registerPath),request({deviceToken:apns}));
  assert.equal((await call(app.routes.get(unregisterPath),request({}))).payload.registered,false);
  assert.equal(pushes.size,0);
  await call(app.routes.get(registerPath),request({deviceToken:apns}));
  const r=await service.saveAutoCouponPreferences({clientId,preferences:{...prefs,requested:false}});
  assert.equal(r.status,200);assert.equal(pushes.size,0);
});

test('no spoofed client, no permissive unregister body',async()=>{
  const {app}=setup();
  assert.equal((await call(app.routes.get(unregisterPath),request({clientId}))).code,400);
  assert.equal((await call(app.routes.get(unregisterPath),request({},'Bearer '+ 'z'.repeat(43)))).code,401);
});
