'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {registerLearningRoutes}=require('../learning/learning_routes');
const {validatedTarget,run}=require('../daily_palinsesto/trigger_dispatch');

const source=p=>fs.readFileSync(path.join(__dirname,'../..',p),'utf8');
const token='x'.repeat(40);

function app() {
  const routes=new Map();
  return {
    routes,
    get(p,...handlers){routes.set('GET '+p,handlers);},
    post(p,...handlers){routes.set('POST '+p,handlers);},
  };
}
const res=()=>({code:200,payload:null,
  status(n){this.code=n;return this;},json(x){this.payload=x;return this;}});

test('B73: new routes exist but reject registration, push and cron by default',()=>{
  const a=app();
  registerLearningRoutes(a,{env:{},requestApiFootball:async()=>{throw Error('unused');}});
  const status=res();
  a.routes.get('GET /learning/v1/status')[0]({},status);
  assert.equal(status.payload.dailyPalinsestoRegistrationEnabled,false);
  assert.equal(status.payload.dailyPalinsestoPushEnabled,false);
  const reg=res();
  a.routes.get('POST /learning/v1/mobile/palinsesto/subscribe')[0]({get:()=>null},reg,()=>{});
  assert.equal(reg.code,503);
  const push=res();
  a.routes.get('POST /learning/v1/palinsesto/worker/dispatch')[0]({},push);
  assert.equal(push.code,503);
});

test('B73: a protected morning dispatcher is not the old AutoSchedina worker',()=>{
  const routes=source('backend/learning/learning_routes.js');
  assert.match(routes,/\/learning\/v1\/mobile\/palinsesto\/subscribe/);
  assert.match(routes,/\/learning\/v1\/mobile\/palinsesto\/unsubscribe/);
  assert.match(routes,/\/learning\/v1\/palinsesto\/worker\/dispatch/);
  assert.match(routes,/DAILY_PALINSESTO_SCHEMA_READY/);
  assert.match(routes,/DAILY_PALINSESTO_REGISTRATION_ENABLED/);
  assert.match(routes,/x-goalvdline-palinsesto-worker-token/);
  assert.doesNotMatch(source('backend/daily_palinsesto/dispatch.js'),
    /auto_coupon\/generation_coordinator|generateOfficialCoupon/);
  const ios=source('lib/services/goalvdline_palinsesto_digest_registration.dart');
  assert.doesNotMatch(ios,/auto-coupon|automatic.*coupon/i);
  assert.match(ios,/requestDeviceToken/);
});

test('B73: cron needs HTTPS and exact protected route; never guesses secrets',()=>{
  assert.equal(validatedTarget({}),null);
  assert.equal(validatedTarget({
    DAILY_PALINSESTO_DISPATCH_URL:'http://localhost/learning/v1/palinsesto/worker/dispatch',
    DAILY_PALINSESTO_WORKER_TOKEN:token,
  }),null);
  assert.equal(validatedTarget({
    DAILY_PALINSESTO_DISPATCH_URL:'https://example.org/wrong',
    DAILY_PALINSESTO_WORKER_TOKEN:token,
  }),null);
  assert.ok(validatedTarget({
    DAILY_PALINSESTO_DISPATCH_URL:'https://api.example.org/learning/v1/palinsesto/worker/dispatch',
    DAILY_PALINSESTO_WORKER_TOKEN:token,
  }));
});

test('B73: trigger batches bounded pages and stops on day-claim completion',async()=>{
  const cursor='a'.repeat(64);
  let calls=0;
  const result=await run({
    env:{
      DAILY_PALINSESTO_DISPATCH_URL:'https://api.example.org/learning/v1/palinsesto/worker/dispatch',
      DAILY_PALINSESTO_WORKER_TOKEN:token,
    },
    fetchImpl:async (_url,request)=>{
      calls++;
      assert.equal(request.headers['x-goalvdline-palinsesto-worker-token'],token);
      const body=JSON.parse(request.body);
      assert.equal(body.limit,25);
      return {ok:true,json:async()=>({
        status:'checked',sent:1,nextCursor:calls===1?cursor:null,
      })};
    },
  });
  assert.equal(result.status,'completed');
  assert.equal(result.pages,2);
  assert.equal(result.sent,2);
  assert.equal(calls,2);
});
