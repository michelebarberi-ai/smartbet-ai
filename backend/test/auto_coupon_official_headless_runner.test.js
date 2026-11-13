'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createHeadlessEngineHost, validateRequest} = require('../auto_coupon/official_headless_runner');
const {createOfficialEngineAdapter, PROTOCOL} = require('../auto_coupon/official_engine_client');

const TOKEN = 'M'.repeat(48);
const REVISION = 'eac3323';
const NOW = new Date('2026-11-09T08:15:00Z');
const preferences = {requested:true,hour:8,minute:0,events:3,
  minimumMarketProbability:65,market:'MULTI',notifyChanges:true};
const request = {protocol:PROTOCOL,dayKey:'2026-11-09',
  generatedAfter: NOW.toISOString(), preferences};
const coupon = {events:[1,2,3].map(fixtureId=>({fixtureId,
  market:'HCP EURO CASA -3 2',marketProbability:82,
  kickoffAt:'2026-11-09T18:00:00.000Z',odds:1.5}))};

async function host(runGenerator, clock=()=>NOW) {
  const server = createHeadlessEngineHost({token:TOKEN,revision:REVISION,
    execute:runGenerator,now:clock});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  return {server,origin,stop:()=>new Promise(resolve=>server.close(resolve))};
}
async function req(origin, method, pathname, token=TOKEN, body=null) {
  return fetch(origin+pathname,{method,
    headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
    ...(body ? {body:JSON.stringify(body)} : {})});
}

test('rejects invalid, stale and cross-day request before engine invocation', async()=>{
  assert.equal(validateRequest(request,NOW),true);
  assert.equal(validateRequest({...request,dayKey:'2026-11-10'},NOW),false);
  assert.equal(validateRequest({...request,preferences:{...preferences,events:16}},NOW),false);
  assert.equal(validateRequest({...request,generatedAfter:'2026-11-01T08:00:00Z'},NOW),false);
  assert.equal(validateRequest({...request,clientId:'hidden'},NOW),false);
});

test('headless host authenticates, deduplicates and publishes only finished verified coupon',async()=>{
  let resolve;
  let calls=0;
  const pending = new Promise(r=>{resolve=r;});
  const h = await host(async()=>{calls++;await pending;return {
    protocol:PROTOCOL, officialEngine:true, revision:REVISION, status:'ready', coupon,
  };});
  try {
    assert.equal((await req(h.origin,'POST','/coupon/generate','wrong',request)).status,401);
    assert.equal((await req(h.origin,'POST','/coupon/generate',TOKEN,{...request,clientId:'a'})).status,400);
    let res=await req(h.origin,'POST','/coupon/generate',TOKEN,request);
    assert.equal(res.status,202);
    const jobId=(await res.json()).jobId;
    assert.match(jobId,/^[a-f0-9]{32}$/);
    res=await req(h.origin,'POST','/coupon/generate',TOKEN,request);
    assert.equal((await res.json()).jobId,jobId);
    assert.equal(calls,1);
    assert.equal((await req(h.origin,'GET',`/coupon/jobs/${jobId}`)).status,202);
    resolve();
    for(let i=0;i<20;i++) {
      await new Promise(r=>setTimeout(r,5));
      res=await req(h.origin,'GET',`/coupon/jobs/${jobId}`);
      if(res.status===200)break;
    }
    assert.equal(res.status,200);
    const output=await res.json();
    assert.equal(output.revision,REVISION);
    assert.deepEqual(output.coupon,coupon);
    assert.equal(JSON.stringify(output).includes(TOKEN),false);
    assert.equal((await req(h.origin,'GET',`/coupon/jobs/${jobId}`,'wrong')).status,401);
  } finally {await h.stop();}
});

test('runner rejects underthreshold output and does not expose it',async()=>{
  const badCoupon={events:coupon.events.map((x,i)=>({...x,
    marketProbability:i===0?10:82}))};
  const h=await host(async()=>({protocol:PROTOCOL,officialEngine:true,
    revision:REVISION,status:'ready',coupon:badCoupon}));
  try {
    const begin=await req(h.origin,'POST','/coupon/generate',TOKEN,request);
    const jobId=(await begin.json()).jobId;
    let response;
    for(let i=0;i<20;i++){
      await new Promise(r=>setTimeout(r,5));
      response=await req(h.origin,'GET',`/coupon/jobs/${jobId}`);
      if(response.status!==202)break;
    }
    assert.equal(response.status,503);
    assert.equal(JSON.stringify(await response.json()).includes('10'),false);
  } finally {await h.stop();}
});

test('existing official adapter polls async jobs on the pinned host',async()=>{
  const h=await host(async()=>({protocol:PROTOCOL,officialEngine:true,
    revision:REVISION,status:'ready',coupon}));
  let calls=0;
  try {
    // HTTPS-only address is retained in configuration. The local test adapter
    // reroutes to loopback without changing production URL verification rules.
    const adapter=createOfficialEngineAdapter({clock:()=>NOW,env:{
      AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'true',
      AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://engine.example.org/coupon/generate',
      AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:TOKEN,
      AUTO_COUPON_OFFICIAL_ENGINE_REVISION:REVISION},
      fetchImpl:(url,opts)=>{calls++; return fetch(h.origin+new URL(url).pathname,opts);},
      sleep:()=>Promise.resolve(),maxPolls:50});
    assert.deepEqual(await adapter({dayKey:request.dayKey,now:NOW,preferences}),coupon);
    assert.ok(calls>=2);
  } finally {await h.stop();}
});


test('official no_coupon is distinguished from an engine failure end to end', async () => {
  const h = await host(async () => ({
    protocol:PROTOCOL,officialEngine:true,revision:REVISION,status:'no_eligible_coupon',
  }));
  try {
    const adapter = createOfficialEngineAdapter({
      clock:()=>NOW,
      env:{
        AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'true',
        AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://engine.example.org/coupon/generate',
        AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:TOKEN,
        AUTO_COUPON_OFFICIAL_ENGINE_REVISION:REVISION,
      },
      fetchImpl:(url,opts)=>fetch(h.origin+new URL(url).pathname,opts),
      sleep:()=>Promise.resolve(),maxPolls:100,
    });
    const actual = await adapter({dayKey:request.dayKey,now:NOW,preferences});
    assert.deepEqual(actual,{status:'no_coupon'});
    assert.equal(Object.hasOwn(actual,'coupon'),false);
  } finally {await h.stop();}
});

test('transport or runner failure cannot be mistaken for no_coupon', async () => {
  for (const error of ['failed','provider_unavailable','invalid_stored_result']) {
    const adapter = createOfficialEngineAdapter({
      clock:()=>NOW,
      env:{
        AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'true',
        AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://engine.example.org/coupon/generate',
        AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:TOKEN,
        AUTO_COUPON_OFFICIAL_ENGINE_REVISION:REVISION,
      },
      fetchImpl:async (url) => /\/jobs\//.test(url)
        ? {status:503,headers:{get:()=>null},text:async()=>JSON.stringify({error})}
        : {status:202,headers:{get:()=>null},
          text:async()=>JSON.stringify({protocol:PROTOCOL,jobId:'a'.repeat(32)})},
      sleep:()=>Promise.resolve(),maxPolls:3,
    });
    await assert.rejects(adapter({dayKey:request.dayKey,now:NOW,preferences}),
      /Official engine unavailable/);
  }
});

test('poll rejects malicious ticket and never follows off-host URL',async()=>{
  const adapter=createOfficialEngineAdapter({clock:()=>NOW,env:{
    AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'true',
    AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://engine.example.org/coupon/generate',
    AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:TOKEN,
    AUTO_COUPON_OFFICIAL_ENGINE_REVISION:REVISION},
    fetchImpl:async()=>({status:202,headers:{get:()=>null},text:async()=>JSON.stringify({
      protocol:PROTOCOL,jobId:'../../evil',url:'https://evil.example.org'})}),
    sleep:()=>Promise.resolve()});
  await assert.rejects(adapter({dayKey:request.dayKey,now:NOW,preferences}));
});
