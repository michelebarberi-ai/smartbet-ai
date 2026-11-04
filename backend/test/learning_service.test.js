'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {LearningService} = require('../learning/learning_service');

const fixture = (id,status,date,score) => ({response:[{fixture:{id,date,status:{short:status}},
  score:{fulltime:score},goals:score}]});
const now = () => new Date('2026-11-01T12:00:00Z');
const clientId = 'a7c2b3d4-1111-4111-8111-eeee12345678';
const payload = {clientId, predictions:[{fixtureId:31,engine:'smartBet',market:'OVER 2.5',probability:0.78}]};

function makeRepository() {
  return { initialized:0, inserted:[], pending:[31], resolved:[],
    async initialize(){this.initialized++},
    async insertPrediction(row){this.inserted.push(row);return true},
    async pendingFixtureIds(){return this.pending},
    async resolveFixture(id,h,a,settle){this.resolved.push({id,h,a,result:settle('OVER 2.5',h,a)});return 1},
    checked:[],
    async markChecked(id,date){this.checked.push({id,date})},
    async prune(){return 0},
    async summary(){return []},
  };
}

test('ingest verifies kickoff server side and never accepts claimed outcome', async () => {
  const repo=makeRepository();
  const service=new LearningService({repository:repo, subjectSalt:'secret', now,
    fetchFixture:async id=>fixture(id,'NS','2026-11-01T14:00:00Z')});
  const result=await service.ingest({...payload, predictions:[{...payload.predictions[0],status:'correct'}]});
  assert.equal(result.status,200);
  assert.equal(repo.inserted.length,1);
  assert.equal(repo.inserted[0].status,undefined);
  assert.equal(repo.inserted[0].subjectHash.length,64);
  assert.equal(repo.inserted[0].kickoff.toISOString(),'2026-11-01T14:00:00.000Z');
});

test('ingest fails closed for in-progress fixtures and API mismatches', async () => {
  const repo=makeRepository();
  const inProgress=new LearningService({repository:repo,subjectSalt:'secret',now,
    fetchFixture:async id=>fixture(id,'1H','2026-11-01T11:00:00Z')});
  assert.equal((await inProgress.ingest(payload)).status,422);
  assert.equal(repo.inserted.length,0);
  const badId=new LearningService({repository:repo,subjectSalt:'secret',now,
    fetchFixture:async id=>fixture(id+1,'NS','2026-11-01T14:00:00Z')});
  assert.equal((await badId.ingest(payload)).status,422);
});

test('resolve obtains result from provider, skips unfinished and does not accept app score', async () => {
  const repo=makeRepository();
  const service=new LearningService({repository:repo,subjectSalt:'secret',now,
    fetchFixture:async id=>fixture(id,'FT','2026-10-30T14:00:00Z',{home:2,away:1})});
  const result=await service.resolve();
  assert.equal(result.resolvedFixtures,1);
  assert.equal(repo.resolved[0].result,true);
  assert.equal(result.errors,0);
  const pending=new LearningService({repository:repo,subjectSalt:'secret',now,
    fetchFixture:async id=>fixture(id,'HT','2026-11-01T12:00:00Z')});
  assert.equal((await pending.resolve()).skipped,1);
});

test('summary never authorizes live calibration', async()=>{
  const service=new LearningService({repository:makeRepository(),subjectSalt:'secret',now,fetchFixture:async()=>{}});
  assert.deepEqual(await service.summary(), {success:true, mode:'research_only', appliesToLivePredictions:false, markets:[]});
});


test('resolver rotates skipped and failing fixtures without treating them as settled', async () => {
  const repo=makeRepository();
  repo.pending=[31,32,33];
  const service=new LearningService({repository:repo, subjectSalt:'secret', now,
    fetchFixture: async id => {
      if (id===31) return fixture(id,'HT','2026-11-01T10:00:00Z');
      if (id===32) throw Error('provider temporarily unavailable');
      return fixture(id,'FT','2026-10-30T12:00:00Z',{home:2,away:1});
    }});
  const result=await service.resolve();
  assert.equal(result.attemptedFixtures,3);
  assert.equal(result.skipped,1);
  assert.equal(result.errors,1);
  assert.equal(result.updatedRecords,1);
  assert.deepEqual(repo.checked.map(x=>x.id),[31,32,33]);
});
