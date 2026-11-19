'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {validatedTarget,run}=require('../daily_palinsesto/trigger_dispatch');

test('B73: missing GitHub secrets makes dispatch inert',async()=>{
  assert.equal(validatedTarget({}),null);
  assert.deepEqual(await run({env:{},fetchImpl:async()=>{throw Error('must not call')}}),
    {status:'disabled',pages:0});
});
test('B73: only trusted HTTPS worker endpoint is accepted',()=>{
  const workerToken='t'.repeat(40);
  assert.equal(validatedTarget({DAILY_PALINSESTO_DISPATCH_URL:
    'http://localhost/learning/v1/palinsesto/worker/dispatch',
    DAILY_PALINSESTO_WORKER_TOKEN:workerToken}),null);
  assert.ok(validatedTarget({DAILY_PALINSESTO_DISPATCH_URL:
    'https://goalvdline-learning-api.onrender.com/learning/v1/palinsesto/worker/dispatch',
    DAILY_PALINSESTO_WORKER_TOKEN:workerToken}));
});
test('B73: dispatch batches only requested calendar updates',async()=>{
  let sends=0;
  const result=await run({env:{
    DAILY_PALINSESTO_DISPATCH_URL:
      'https://goalvdline-learning-api.onrender.com/learning/v1/palinsesto/worker/dispatch',
    DAILY_PALINSESTO_WORKER_TOKEN:'t'.repeat(40),
  },fetchImpl:async(_url,options)=>{
    sends++;
    assert.equal(options.method,'POST');
    assert.equal(JSON.parse(options.body).limit,25);
    return {ok:true,json:async()=>({
      status:'checked',sent:1,nextCursor:null,
    })};
  }});
  assert.equal(result.status,'completed');
  assert.equal(result.sent,1);
  assert.equal(sends,1);
});
