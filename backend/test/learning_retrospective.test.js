'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {validateRetrospective} = require('../learning/learning_retrospective');
const {LearningService} = require('../learning/learning_service');
const {registerLearningRoutes} = require('../learning/learning_routes');
const now = new Date('2026-11-08T18:00:00Z');
const row = {kind: 'retrospective_unverified_v1', fixtureId: 1234,
  engine: 'smartBet', market: 'OVER 2.5', probability: 0.73,
  firstSeenAt: '2026-10-01T12:00:00Z', kickoffAt: '2026-10-02T12:00:00Z',
  localStatusHint: 'correct'};
const env = {LEARNING_SERVER_ENABLED: 'true', LEARNING_MOBILE_INGEST_ENABLED: 'true',
  LEARNING_RETRO_INGEST_ENABLED: 'true', DATABASE_URL: 'postgres://fake',
  LEARNING_ADMIN_TOKEN: 'A'.repeat(40), LEARNING_SUBJECT_SALT: 'S'.repeat(40)};
function fakeApp() {const routes = new Map(); return {routes,
  get(k,...v){routes.set(`GET ${k}`,v);},post(k,...v){routes.set(`POST ${k}`,v);}};}
function res() {return {code:200, payload:null, headers:{},status(c){this.code=c;return this;},
  json(d){this.payload=d;return this;},set(k,v){this.headers[k]=v;return this;}};}
function req(token, body) {return {body,get(k){return k==='authorization' ? `Bearer ${token}` : null;}};}
function fixture() {throw new Error('Historical ingestion must not call football provider');}
function service() {const state = {rows:[],clients:new Map()};
  const repository = {async initialize(){},async insertRetrospectiveBatch({subjectHash,snapshots}){
    state.rows.push({subjectHash,snapshots});return snapshots.length;},
    async findValidClient(hash){return state.clients.get(hash)||null;}};
  return {state, service:new LearningService({repository,fetchFixture:fixture,
    subjectSalt: env.LEARNING_SUBJECT_SALT,now:()=>now})};}
const token = 'A'.repeat(43);
test('rejects future, unverified timestamps, malformed records and duplicate items',()=>{
  assert.equal(validateRetrospective({snapshots:[row]},now).length,1);
  for (const bad of [{...row,kind:'prospective'}, {...row,firstSeenAt:'2026-10-03T12:00:00Z'},
    {...row,firstSeenAt:'2026-10-01T12:00:00'}, {...row,kickoffAt:'2026-11-10T12:00:00Z'},
    {...row,probability:2}, {...row,localStatusHint:'verified'}]) {
      assert.equal(validateRetrospective({snapshots:[bad]},now),null);
  }
  assert.equal(validateRetrospective({snapshots:[row,row]},now),null);
  assert.equal(validateRetrospective({snapshots:Array(101).fill(row)},now),null);
});
test('retrospective is isolated and disabled by default',async()=>{
  const {service:svc,state} = service();const app=fakeApp();
  registerLearningRoutes(app,{env:{...env,LEARNING_RETRO_INGEST_ENABLED:'false'}, learningService:svc});
  const status=res();app.routes.get('GET /learning/v1/status')[0]({},status);
  assert.equal(status.payload.retrospectiveIngestEnabled,false);
  const handlers=app.routes.get('POST /learning/v1/mobile/retrospective');
  state.clients.set(crypto.createHash('sha256').update(token).digest('hex'),'device-id');
  const request=req(token,{snapshots:[row]});const response=res();
  await handlers[0](request,response,()=>handlers[1](request,response));
  assert.equal(response.code,503);assert.equal(state.rows.length,0);
});
test('mobile token required, no spoofing, server stores separately without fixture lookup',async()=>{
  const {service:svc,state}=service();const app=fakeApp();
  registerLearningRoutes(app,{env,learningService:svc});
  const handlers=app.routes.get('POST /learning/v1/mobile/retrospective');
  const unauth={body:{snapshots:[row]},get(){return null;}};
  const denied=res();await handlers[0](unauth,denied,()=>{throw Error('unauth');});
  assert.equal(denied.code,401);
  state.clients.set(crypto.createHash('sha256').update(token).digest('hex'),'device-id');
  const spoof=req(token,{clientId:'other',snapshots:[row]});const spoofed=res();
  await handlers[0](spoof,spoofed,()=>handlers[1](spoof,spoofed));
  assert.equal(spoofed.code,400);
  const request=req(token,{snapshots:[row]});const response=res();
  await handlers[0](request,response,()=>handlers[1](request,response));
  assert.equal(response.code,200);assert.equal(response.payload.accepted,1);
  assert.equal(response.payload.appliesToLivePredictions,false);
  assert.equal(state.rows.length,1);
  assert.equal(state.rows[0].subjectHash,
    crypto.createHmac('sha256',env.LEARNING_SUBJECT_SALT).update('device-id').digest('hex'));
  assert.equal(state.rows[0].snapshots[0].localStatusHint,'correct');
});
