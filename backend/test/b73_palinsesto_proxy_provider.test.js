'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {fetchDailyFixtures}=require('../daily_palinsesto/provider');

function feed(id) {
  return {response:[{fixture:{id,date:'2026-11-21T15:00:00Z',status:{short:'NS'}},
    league:{id:135,name:'Serie A',country:'Italia'}}],errors:[]};
}

test('B73: daily digest uses existing SmartBet fixtures proxy without key or odds calls',async()=>{
  let requests=0;
  const result=await fetchDailyFixtures('2026-11-21',{
    now:()=>10000,
    fetchImpl:async (url,init)=>{
      requests++;
      assert.equal(url.origin,'https://smartbet-ai-y6gw.onrender.com');
      assert.equal(url.pathname,'/football/fixtures');
      assert.equal(url.searchParams.get('date'),'2026-11-21');
      assert.equal(url.searchParams.get('timezone'),'Europe/Rome');
      assert.equal(init.method,'GET');
      assert.equal(init.redirect,'error');
      assert.equal(init.headers['x-apisports-key'],undefined);
      return {ok:true,json:async()=>feed(1001)};
    },
  });
  assert.equal(result.response.length,1);
  assert.equal(requests,1);
  const cached=await fetchDailyFixtures('2026-11-21',{
    now:()=>10001,fetchImpl:async()=>{throw Error('Should use cache');},
  });
  assert.equal(cached.response[0].fixture.id,1001);
});

test('B73: concurrent fixture requests share a single in-flight read',async()=>{
  let requested=0;
  const fetchImpl=async()=>{
    requested++;
    await new Promise(resolve=>setImmediate(resolve));
    return {ok:true,json:async()=>feed(1002)};
  };
  const opts={now:()=>20000,fetchImpl};
  const [a,b]=await Promise.all([
    fetchDailyFixtures('2026-11-22',opts),
    fetchDailyFixtures('2026-11-22',opts),
  ]);
  assert.equal(requested,1);
  assert.deepEqual(a,b);
});

test('B73: provider 429 or invalid feed never becomes zero matches',async()=>{
  for(const [date,reply] of [
    ['2026-11-23',{ok:false,status:429}],
    ['2026-11-24',{ok:true,json:async()=>({errors:{requests:'rate limit'}})}],
  ]){
    await assert.rejects(()=>fetchDailyFixtures(date,{
      now:()=>25000,fetchImpl:async()=>reply,
    }),/unavailable|invalid/i);
  }
});

test('B73: strict origin and date guard prevent arbitrary proxy requests',async()=>{
  await assert.rejects(()=>fetchDailyFixtures('bad',{fetchImpl:async()=>{}}),/Invalid/);
  await assert.rejects(()=>fetchDailyFixtures('2026-11-25',{
    origin:'https://untrusted.example.org',fetchImpl:async()=>{},
  }),/Untrusted/);
});
