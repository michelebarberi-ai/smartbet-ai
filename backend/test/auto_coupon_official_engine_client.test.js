'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {PROTOCOL, officialEngineConfiguration, createOfficialEngineAdapter} =
  require('../auto_coupon/official_engine_client');

const REV = 'eac3323';
const SECRET = 'e'.repeat(48);
const ENV = {AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'true',
  AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://official.example.org/coupon/generate',
  AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:SECRET,
  AUTO_COUPON_OFFICIAL_ENGINE_REVISION:REV};
const NOW = new Date('2026-11-09T08:15:00Z');
const PREFS = {requested:true,hour:8,minute:0,events:3,
  minimumMarketProbability:65,market:'MULTI',notifyChanges:true};
const COUPON = {events:[1,2,3].map(fixtureId => ({fixtureId,
  market:'1X2',marketProbability:72,kickoffAt:'2026-11-09T18:00:00Z',odds:1.85}))};
const response = (payload, status=200, contentLength=null) => ({status,
  headers:{get:()=>contentLength},text:async()=>JSON.stringify(payload)});
const good = {protocol:PROTOCOL,officialEngine:true,revision:REV,coupon:COUPON};
const args = {dayKey:'2026-11-09',preferences:PREFS,now:NOW,subjectHash:'0'.repeat(64)};

test('engine transport remains OFF without explicit feature flag, pin and secret',()=>{
  for (const env of [ {},{...ENV,AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'false'},
    {...ENV,AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:'short'},
    {...ENV,AUTO_COUPON_OFFICIAL_ENGINE_REVISION:'unversioned'},
    {...ENV,AUTO_COUPON_OFFICIAL_ENGINE_URL:'http://official.example.org/coupon/generate'},
    {...ENV,AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://user:pass@official.example.org/coupon/generate'},
    {...ENV,AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://official.example.org/coupon/generate?key=secret'},
    {...ENV,AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://official.example.org/'}]) {
    assert.equal(createOfficialEngineAdapter({clock:()=>NOW,env}),null);
  }
});

test('valid configuration never leaks the secret in URL',()=>{
  const settings = officialEngineConfiguration(ENV);
  assert.equal(settings.url,'https://official.example.org/coupon/generate');
  assert.equal(settings.url.includes(SECRET),false);
});

test('only a pinned official engine can return a valid pre-match coupon',async()=>{
  let request;
  const engine = createOfficialEngineAdapter({clock:()=>NOW,env:ENV,fetchImpl:async(url,options)=>{
    request={url,options};return response(good);
  }});
  assert.deepEqual(await engine(args),COUPON);
  assert.equal(request.options.redirect,'error');
  assert.equal(request.options.method,'POST');
  assert.equal(request.options.headers.Authorization,`Bearer ${SECRET}`);
  const body=JSON.parse(request.options.body);
  assert.equal(body.protocol,PROTOCOL);
  assert.equal(body.dayKey,args.dayKey);
  assert.equal(body.generatedAfter,NOW.toISOString());
  assert.deepEqual(body.preferences,PREFS);
  assert.equal(request.options.body.includes(args.subjectHash),false);
  assert.equal(request.options.body.includes(SECRET),false);
});

test('rejects wrong model revision, unverified source and malformed payload',async()=>{
  for(const payload of [ {...good,revision:'fbe2771'},
    {...good,officialEngine:false},{...good,protocol:'unknown'},
    {success:true,coupon:COUPON},null,'invalid']) {
    const engine = createOfficialEngineAdapter({clock:()=>NOW,env:ENV,fetchImpl:async()=>response(payload)});
    await assert.rejects(engine(args));
  }
});

test('rejects invalid coupons even if remote claims to be official',async()=>{
  for(const coupon of [
    {events:[...COUPON.events.slice(0,2)]},
    {events:COUPON.events.map((event,index)=>({...event,marketProbability:index===0?12:72}))},
    {events:COUPON.events.map((event,index)=>({...event,fixtureId:index===1?1:event.fixtureId}))},
    {events:COUPON.events.map(event=>({...event,kickoffAt:'2026-11-10T18:00:00Z'}))},
  ]) {
    const engine=createOfficialEngineAdapter({clock:()=>NOW,env:ENV,fetchImpl:async()=>response({...good,coupon})});
    await assert.rejects(engine(args));
  }
});

test('network failures, non-200, oversized and broken JSON fail closed',async()=>{
  const badResponses=[async()=>response(good,401),async()=>response(good,500),
    async()=>response(good,200,65537),async()=>({status:200,headers:{get:()=>null},
      text:async()=>'{invalid'}),async()=>{throw Error('private provider error')}];
  for(const fetchImpl of badResponses) {
    const engine=createOfficialEngineAdapter({clock:()=>NOW,env:ENV,fetchImpl});
    await assert.rejects(engine(args));
  }
});

test('only same-day validated requests can invoke official engine',async()=>{
  let called=0;
  const engine=createOfficialEngineAdapter({clock:()=>NOW,env:ENV,fetchImpl:async()=>{called++;return response(good)}});
  await assert.rejects(engine({...args,dayKey:'INVALID'}));
  await assert.rejects(engine({...args,now:new Date('invalid')}));
  assert.equal(called,0);
});

test('late official response is rejected if any match has kicked off meanwhile',async()=>{
  const clock=()=>new Date('2026-11-09T19:01:00Z');
  const engine=createOfficialEngineAdapter({env:ENV,clock,
    fetchImpl:async()=>response(good)});
  await assert.rejects(engine(args),/Invalid official coupon/);
});
