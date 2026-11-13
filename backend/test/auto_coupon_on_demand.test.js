'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {OnDemandCouponService,normalizeRequest,oddsStrictlyAboveMinimum}=
  require('../auto_coupon/on_demand_coupon_service');
const {registerOnDemandCouponRoutes,BASE,WORKER}=
  require('../auto_coupon/on_demand_coupon_routes');

const clientId='11111111-1111-4111-8111-111111111111';
const serverTime=new Date('2026-11-13T12:00:00Z');
const secret='s'.repeat(40);
const workerToken='w'.repeat(48);
const requestId='22222222-2222-4222-8222-222222222222';
const input={requestId,events:3,minimumMarketProbability:65,market:'MULTI',
  systemMode:'SINGLE',windowDays:1};
const events=[1,2,3].map(i=>({fixtureId:i,market:'OVER 1.5',
  marketProbability:85,kickoffAt:'2026-11-13T18:00:00Z',odds:1.32}));
const coupon={events};

function fakeRepo() {
  const jobs=new Map();
  let initialized=0;
  let claims=0;
  const repo={jobs,get initialized(){return initialized;},get claims(){return claims;},
    async initialize(){initialized++;},
    async enqueueOnDemandCoupon({subjectHash,requestId:rid,dayKey,preferences}) {
      for(const j of jobs.values()){
        if(j.subjectHash===subjectHash && j.requestId===rid) {
          return JSON.stringify(j.preferences)===JSON.stringify(preferences) ?
            {jobId:j.jobId,dayKey,status:j.status} : {conflict:true};
        }
      }
      const j={jobId:randomUUID(),subjectHash,requestId:rid,dayKey,
        preferences,status:'queued',attempts:0};
      jobs.set(j.jobId,j);
      return {jobId:j.jobId,dayKey,status:j.status};
    },
    async readOnDemandCoupon({subjectHash,jobId}){
      const j=jobs.get(jobId);
      return j?.subjectHash===subjectHash?j:null;
    },
    async claimOnDemandCoupon(){
      const j=[...jobs.values()].find(v=>v.status==='queued');
      if(!j)return null;
      claims++;
      j.status='running';j.attempts++;j.leaseToken=randomUUID();
      return {...j};
    },
    async renewOnDemandCouponLease({jobId,attempts,leaseToken}){
      const j=jobs.get(jobId);
      return j?.status==='running' && j.attempts===attempts && j.leaseToken===leaseToken;
    },
    async finishOnDemandCoupon({jobId,attempts,leaseToken,outcome,coupon:data}){
      const j=jobs.get(jobId);
      if(!j||j.status!=='running'||j.attempts!==attempts||j.leaseToken!==leaseToken)
        return false;
      j.status=outcome==='retry'?'queued':outcome;
      j.coupon=data??null;
      j.leaseToken=null;
      return true;
    },
  };return repo;
}
function service(repo,generateOfficialCoupon=async()=>coupon) {
  return new OnDemandCouponService({repository:repo,subjectSalt:secret,
    generateOfficialCoupon,now:()=>serverTime,leaseRenewalMs:100000});
}
function fakeApp(){
  const routes=new Map();
  return {routes,
    get(p,...handlers){routes.set('GET '+p,handlers);},
    post(p,...handlers){routes.set('POST '+p,handlers);},
  };
}
function response(){
  return {code:200,body:null,status(c){this.code=c;return this;},
    json(v){this.body=v;return this;},set(){return this;}};
}
const fakeAuthorize=(_,__,next)=>next();
async function call(app,method,path,body={},params={}) {
  const handlers=app.routes.get(method+' '+path);
  assert.ok(handlers);
  const res=response();
  const req={body,params,learningClientId:clientId,get:()=>workerToken};
  for(const handler of handlers){
    let next=false;
    await handler(req,res,()=>{next=true;});
    if(!next)break;
  }
  return res;
}
const env={
  ON_DEMAND_COUPON_REQUESTS_ENABLED:'true',
  ON_DEMAND_COUPON_WORKER_ENABLED:'true',
  ON_DEMAND_COUPON_WORKER_TOKEN:workerToken,
  LEARNING_SUBJECT_SALT:secret,
};

test('B47: request validation rejects unknown fields, invalid UUID and flags',()=>{
  assert.equal(normalizeRequest(input)?.preferences.events,3);
  for(const v of [{...input,clientId},{...input,events:16},
      {...input,minimumMarketProbability:12},
      {...input,requestId:'spoof'},
      {...input,market:'UNSUPPORTED'},
      {...input,unknown:'x'}]) {
    assert.equal(normalizeRequest(v),null);
  }
});

test('B47: missing engine rejects mobile work without database write',async()=>{
  const repo=fakeRepo(),s=service(repo,null);
  const r=await s.submit({clientId,body:input});
  assert.equal(r.status,503);
  assert.equal(repo.initialized,0);
});

test('B47: request idempotency and client isolation survive app closing',async()=>{
  const repo=fakeRepo(),s=service(repo);
  const first=await s.submit({clientId,body:input});
  assert.equal(first.status,202);
  const repeated=await s.submit({clientId,body:input});
  assert.equal(repeated.body.jobId,first.body.jobId);
  const pending=await s.read({clientId,jobId:first.body.jobId});
  assert.equal(pending.body.status,'queued');
  const stranger=await s.read({
    clientId:'33333333-3333-4333-8333-333333333333',
    jobId:first.body.jobId,
  });
  assert.equal(stranger.status,404);
  assert.equal(repo.jobs.size,1);
});

test('B47: worker publishes only validated official forecasts >1.20',async()=>{
  const repo=fakeRepo(),s=service(repo,async()=>({
    ...coupon,secret:'MUST_NOT_STORE',
  }));
  const created=await s.submit({clientId,body:input});
  assert.equal((await s.runOne()).status,'ready');
  const ready=await s.read({clientId,jobId:created.body.jobId});
  assert.equal(ready.status,200);
  assert.equal(ready.body.coupon.events.length,3);
  assert.equal('secret' in ready.body.coupon,false);
  assert.equal((await s.runOne()).status,'idle');
});

test('B47: no invented odds, 1.20 exact not playable',async()=>{
  assert.equal(oddsStrictlyAboveMinimum({events:[{odds:1.20}]}),false);
  assert.equal(oddsStrictlyAboveMinimum(coupon),true);
  const repo=fakeRepo(),s=service(repo,async()=>({
    events:events.map((e,i)=>({...e,odds:i===1?1.20:1.32})),
  }));
  const created=await s.submit({clientId,body:input});
  assert.equal((await s.runOne()).status,'retry');
  const result=await s.read({clientId,jobId:created.body.jobId});
  assert.equal(result.body.status,'queued');
  assert.equal(result.body.coupon,undefined);
});

test('B47: server flags fail closed for requests and worker',async()=>{
  const repo=fakeRepo(),app=fakeApp();
  registerOnDemandCouponRoutes(app,{
    env:{...env,ON_DEMAND_COUPON_REQUESTS_ENABLED:'false'},
    mobileEnabled:true,authorizeMobile:fakeAuthorize,
    getLearningService:()=>({repository:repo}),
    generateOfficialCoupon:async()=>coupon,
    now:()=>serverTime,
  });
  const request=await call(app,'POST',BASE,input);
  const worker=await call(app,'POST',WORKER,{});
  assert.equal(request.code,503);
  assert.equal(worker.code,503);
  assert.equal(repo.initialized,0);
});

test('B47: no request accepted without a running server worker',async()=>{
  const repo=fakeRepo(),app=fakeApp();
  const flags=registerOnDemandCouponRoutes(app,{
    env,mobileEnabled:true,authorizeMobile:fakeAuthorize,
    workerRunning:false,
    getLearningService:()=>({repository:repo}),
    generateOfficialCoupon:async()=>coupon,now:()=>serverTime,
  });
  assert.equal(flags.enabled,false);
  assert.equal(flags.workerEnabled,true); // manual privileged endpoint separate
  const response=await call(app,'POST',BASE,input);
  assert.equal(response.code,503);
  assert.equal(repo.initialized,0);
});

test('B47: worker auth and mobile route do not leak engine credentials',async()=>{
  const repo=fakeRepo(),app=fakeApp();
  registerOnDemandCouponRoutes(app,{
    env,mobileEnabled:true,authorizeMobile:fakeAuthorize,
    workerRunning:true,
    getLearningService:()=>({repository:repo}),
    generateOfficialCoupon:async()=>coupon,now:()=>serverTime,
  });
  const queued=await call(app,'POST',BASE,input);
  assert.equal(queued.code,202);
  assert.equal(JSON.stringify(queued.body).includes(workerToken),false);
  const handlers=app.routes.get('POST '+WORKER);
  const res=response();
  await handlers[0]({body:{},get:()=> 'not-the-token'},res);
  assert.equal(res.code,401);
  assert.equal((await call(app,'POST',WORKER,{})).body.status,'ready');
  const result=await call(app,'GET',BASE+'/:jobId',{},
    {jobId:queued.body.jobId});
  assert.equal(result.code,200);
  assert.equal(result.body.status,'ready');
});
