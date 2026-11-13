'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createLearningOnlyApp} = require('../learning_only_server');

const TOKEN = 'b'.repeat(48);
const REVISION = 'a'.repeat(40);
const CONFIG = {
  AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'true',
  AUTO_COUPON_OFFICIAL_ENGINE_PRIVATE_RENDER_ENABLED:'true',
  AUTO_COUPON_OFFICIAL_ENGINE_HOSTPORT:'smartbet-b45-flutter-staging:8799',
  AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:TOKEN,
  AUTO_COUPON_OFFICIAL_ENGINE_REVISION:REVISION,
  ON_DEMAND_COUPON_REQUESTS_ENABLED:'false',
  ON_DEMAND_COUPON_SERVER_POLL_ENABLED:'false',
};

async function runHealth(env,fetchImpl) {
  const app=createLearningOnlyApp({env,fetchImpl});
  const server=await new Promise(resolve=>{
    const instance=app.listen(0,'127.0.0.1',()=>resolve(instance));
  });
  try {
    const res=await fetch('http://127.0.0.1:'+server.address().port+
      '/health/official-engine');
    return {status:res.status,body:await res.json()};
  } finally {
    await new Promise(resolve=>server.close(resolve));
  }
}

test('private runner health requires independently validated configured transport',async()=>{
  let calls=0;
  const result=await runHealth({},async()=>{calls++;throw new Error('unexpected request');});
  assert.equal(result.status,503);
  assert.deepEqual(result.body,{
    engineConfigured:false,engineReachable:false,engineVerified:false});
  assert.equal(calls,0);
});

test('private runner health confirms authentication, revision and protocol without a job',async()=>{
  let called=0;
  const result=await runHealth(CONFIG,async (url,request)=>{
    called++;
    assert.equal(url.hostname,'smartbet-b45-flutter-staging');
    assert.equal(url.pathname,'/coupon/health');
    assert.equal(request.method,'GET');
    assert.equal(request.headers.Authorization,'Bearer '+TOKEN);
    assert.equal(request.redirect,'error');
    return {status:200,json:async()=>({
      protocol:'goalvdline-official-coupon-v1',
      officialEngine:true,revision:REVISION,ready:true,
    })};
  });
  assert.equal(result.status,200);
  assert.equal(result.body.engineVerified,true);
  assert.equal(called,1);
});

test('private runner health rejects bad revision or authentication',async()=>{
  for (const status of [200,401]) {
    const result=await runHealth(CONFIG,async()=>({
      status,
      json:async()=>({protocol:'goalvdline-official-coupon-v1',
        officialEngine:true,revision:'f'.repeat(40),ready:true}),
    }));
    assert.equal(result.status,503);
    assert.equal(result.body.engineVerified,false);
  }
});
