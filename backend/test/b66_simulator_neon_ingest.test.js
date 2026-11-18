'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {validateBatch} = require('../learning/learning_core');
const {LearningService} = require('../learning/learning_service');
const {LearningRepository} = require('../learning/learning_repository');
const {registerLearningRoutes} = require('../learning/learning_routes');

const clientId = 'a7c2b3d4-1111-4111-8111-eeee12345678';
const simulator = {
  fixtureId: 123, engine: 'simulator', market: 'GOAL',
  probability: 0.73, inputSource: 'smartBet',
};
const payload = {clientId, predictions: [simulator]};

test('B66: third engine is rejected by default and source is mandatory', () => {
  assert.equal(validateBatch(payload), null);
  assert.equal(validateBatch(payload, {allowSimulator: true}).predictions[0].inputSource, 'smartBet');
  for (const inputSource of [undefined, '', 'external', 'simulator']) {
    assert.equal(validateBatch({clientId, predictions:[{...simulator, inputSource}]},
      {allowSimulator: true}), null);
  }
  for (const market of ['CORNER', 'OVER 5.5', 'HCP EURO CASA -1 1']) {
    assert.equal(validateBatch({clientId, predictions:[{...simulator, market}]},
      {allowSimulator: true}), null);
  }
  assert.equal(validateBatch({clientId, predictions:[{...simulator, firstSeenAt:'fake'}]},
    {allowSimulator: true}), null);
  assert.equal(validateBatch({clientId, predictions:[
    {...simulator,engine:'smartBet',inputSource:'diego'}]}, {allowSimulator:true}), null);
  // Two markets on the same fixture are allowed, but not the same market twice.
  assert.equal(validateBatch({clientId, predictions: [simulator, simulator]},
    {allowSimulator:true}), null);
  assert.equal(validateBatch({clientId, predictions: [simulator, {...simulator,market:'X'}]},
    {allowSimulator:true}).predictions.length, 2);
});

function makeService(allowSimulator = false) {
  const inserted = [];
  const repository = {
    async initialize() {},
    async insertPrediction(row) {inserted.push(row); return true;},
  };
  const service = new LearningService({
    repository, subjectSalt:'secret', allowSimulator,
    now:()=>new Date('2026-11-18T10:00:00Z'),
    fetchFixture:async id => ({response:[{
      fixture:{id,date:'2026-11-19T12:00:00Z',status:{short:'NS'}},
    }]}),
  });
  return {service, inserted};
}

test('B66: server verifies kickoff, preserves source and never accepts claimed result', async () => {
  const {service,inserted} = makeService(true);
  const result = await service.ingest(payload);
  assert.equal(result.status, 200);
  assert.equal(result.body.accepted, 1);
  assert.equal(inserted[0].engine, 'simulator');
  assert.equal(inserted[0].inputSource, 'smartBet');
  assert.equal(inserted[0].subjectHash.length,64);
  assert.equal(inserted[0].kickoff.toISOString(), '2026-11-19T12:00:00.000Z');

  assert.equal((await makeService(false).service.ingest(payload)).status, 400);
  assert.equal((await service.ingest({clientId,predictions:[
    {...simulator,fixtureId:999,firstSeenAt:'2020-01-01'}
  ]})).status, 400);
});

test('B66: simulator SQL path is separate, parameterized, and idempotent', async () => {
  const calls = [];
  const pool = {async query(sql, params) {
    calls.push({sql,params});
    return {rowCount:calls.length === 1 ? 1 : 0};
  }};
  const repo = new LearningRepository(pool);
  const base = {
    subjectHash:'a'.repeat(64),fixtureId:123,engine:'simulator',
    market:'GOAL',probability:0.73,kickoff:new Date('2026-11-19T12:00:00Z'),
    inputSource:'diego',
  };
  assert.equal(await repo.insertPrediction(base), true);
  assert.match(calls[0].sql,/simulator_input_source/);
  assert.match(calls[0].sql,/ON CONFLICT/);
  assert.equal(calls[0].params[6],'diego');

  assert.equal(await repo.insertPrediction({...base,engine:'smartBet',inputSource:undefined}), false);
  assert.doesNotMatch(calls[1].sql,/simulator_input_source/);
  assert.equal(calls[1].params.length,6);
});

function fakeApp() {
  const routes=new Map();
  return {routes,get(path,...handlers){routes.set('GET '+path,handlers);},
    post(path,...handlers){routes.set('POST '+path,handlers);}};
}
function response() {
  return {code:200,payload:null,headers:{},
    status(n){this.code=n;return this;},
    json(data){this.payload=data;return this;},
    set(k,v){this.headers[k]=v;return this;}};
}
const baseEnv = {
  LEARNING_SERVER_ENABLED:'true',LEARNING_MOBILE_INGEST_ENABLED:'true',
  LEARNING_ADMIN_TOKEN:'A'.repeat(40),
  LEARNING_SUBJECT_SALT:'S'.repeat(40),
  DATABASE_URL:'postgres://fake',
};
const dummyToken = 'a'.repeat(43);
function request(body) {
  return {body,get(name){return name==='authorization'?'Bearer '+dummyToken:null;}};
}
async function exerciseMobile(env, body, nextService) {
  const app=fakeApp();
  registerLearningRoutes(app,{env,
    learningService:{authenticateMobileToken:async()=>clientId,ingest:nextService}});
  const handlers=app.routes.get('POST /learning/v1/mobile/predictions');
  const req=request(body), res=response();
  await handlers[0](req,res,()=>handlers[1](req,res));
  return {res,app};
}

test('B66: two independent flags default off; old mobile uploads still permitted', async () => {
  const app=fakeApp();
  registerLearningRoutes(app,{env:baseEnv,learningService:makeService().service});
  const status=response();
  app.routes.get('GET /learning/v1/status')[0]({},status);
  assert.equal(status.payload.simulatorIngestEnabled,false);

  let invoked=0;
  const denied=await exerciseMobile(
    {...baseEnv,LEARNING_SIMULATOR_INGEST_ENABLED:'true'},
    {predictions:[simulator]},async()=>{invoked++;return {status:200,body:{success:true}};});
  assert.equal(denied.res.code,503);
  assert.equal(invoked,0);
  const normal=await exerciseMobile(baseEnv,{
    predictions:[{fixtureId:123,engine:'smartBet',market:'1',probability:0.7}],
  },async()=>{invoked++;return {status:200,body:{success:true,accepted:1,duplicates:0}};});
  assert.equal(normal.res.code,200);
  assert.equal(invoked,1);
});

test('B66: gated simulator route still requires a mobile bearer credential', async () => {
  const app=fakeApp();
  const env={...baseEnv, LEARNING_SIMULATOR_SCHEMA_READY:'true',
    LEARNING_SIMULATOR_INGEST_ENABLED:'true'};
  registerLearningRoutes(app,{env,learningService:makeService(true).service});
  const status=response();
  app.routes.get('GET /learning/v1/status')[0]({},status);
  assert.equal(status.payload.simulatorIngestEnabled,true);
  const handlers=app.routes.get('POST /learning/v1/mobile/predictions');
  const denied=response();
  await handlers[0]({body:{predictions:[simulator]},get:()=>null},denied,
    ()=>assert.fail('unauthenticated must not proceed'));
  assert.equal(denied.code,401);
});

test('B66: schema migration keeps original predictions and requires provenance', () => {
  const sql=fs.readFileSync(path.join(__dirname,'../learning/migrations/b66_simulator_ingest.sql'),'utf8');
  assert.match(sql,/ADD COLUMN IF NOT EXISTS simulator_input_source/);
  assert.match(sql,/engine IN \('smartBet','diego','simulator'\)/);
  assert.match(sql,/simulator_input_source IS NOT NULL/);
  assert.doesNotMatch(sql,/DELETE FROM|TRUNCATE TABLE|DROP TABLE/i);
});
