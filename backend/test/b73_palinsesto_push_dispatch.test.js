'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {romeMinutes,dispatchDailyPalinsesto}=require('../daily_palinsesto/dispatch');
const {DailyPalinsestoSubscriptionRepository}=
  require('../daily_palinsesto/subscription_repository');
const fs=require('node:fs');
const path=require('node:path');

const now=new Date('2026-11-21T07:05:00Z');
const sha1='a'.repeat(64);
const sha2='b'.repeat(64);
const lockToken='11111111-1111-4111-8111-111111111111';
const env={
  DAILY_PALINSESTO_PUSH_ENABLED:'true',
  DAILY_PALINSESTO_PUSH_TOKEN_ENCRYPTION_KEY:'c'.repeat(64),
  APNS_KEY_ID:'ABCDEFGHIJ',APNS_TEAM_ID:'KLMNOPQRST',
  APNS_BUNDLE_ID:'com.example.goalvdline',
  APNS_ENVIRONMENT:'production',
  APNS_PRIVATE_KEY_BASE64:'ZmFrZS1wcm92aWRlci1rZXk=',
};
const data={response:[
  {fixture:{id:100,date:'2026-11-21T12:00:00Z',status:{short:'NS'}},
    league:{id:135,name:'Serie A',country:'Italia'}},
  {fixture:{id:101,date:'2026-11-21T15:00:00Z',status:{short:'NS'}},
    league:{id:39,name:'Premier League',country:'Inghilterra'}},
]};
function mockRepo(hashes=[sha1,sha2]){
  const records=[];
  return {records,
    listDue:async()=>hashes.map(subjectHash=>({subjectHash})),
    claim:async()=>({attempts:1,lockToken}),
    read:async()=>({environment:'production',ciphertext:'encrypted',nonce:'n',authTag:'t'}),
    finish:async x=>{records.push(x);return true;},
  };
}

test('B73: Rome scheduling correctly follows both DST offsets',()=>{
  assert.equal(romeMinutes(new Date('2026-11-21T07:05:00Z')),485);
  assert.equal(romeMinutes(new Date('2026-07-04T06:05:00Z')),485);
  assert.equal(romeMinutes(new Date('2026-11-21T11:05:00Z')),725);
});

test('B73: one calendar request is shared across all recipients',async()=>{
  const repository=mockRepo();
  let reads=0,sends=0;
  const result=await dispatchDailyPalinsesto({
    repository,env,now:()=>now,
    fetchDailyFixtures:async dayKey=>{reads++;assert.equal(dayKey,'2026-11-21');return data;},
    decrypt:()=> 'd'.repeat(64),
    send:async ({digest})=>{
      sends++;
      assert.equal(digest.fixtureCount,2);
      assert.equal(digest.leagueCount,2);
      return {status:'accepted_by_apns'};
    },
  });
  assert.equal(reads,1);
  assert.equal(sends,2);
  assert.equal(result.sent,2);
  assert.equal(repository.records.length,2);
  assert.ok(repository.records.every(x=>x.dayKey==='2026-11-21'&&x.status==='sent'));
});

test('B73: provider outage creates NO delivery claims or false zero message',async()=>{
  let claims=0;
  const repository=mockRepo([sha1]);
  repository.claim=async()=>{claims++;return {attempts:1,lockToken};};
  const result=await dispatchDailyPalinsesto({repository,env,now:()=>now,
    fetchDailyFixtures:async()=>{throw new Error('503 upstream');},
    send:async()=>{throw new Error('must not send');},
  });
  assert.equal(result.status,'feed_unavailable');
  assert.equal(claims,0);
});

test('B73: default disabled and late dispatch never spend fixture API calls',async()=>{
  let calls=0;
  const repository=mockRepo([sha1]);
  const fetchDailyFixtures=async()=>{calls++;return data;};
  assert.equal((await dispatchDailyPalinsesto({
    repository,env:{},now:()=>now,fetchDailyFixtures,
  })).status,'disabled');
  assert.equal((await dispatchDailyPalinsesto({
    repository,env,now:()=>new Date('2026-11-21T12:05:00Z'),fetchDailyFixtures,
  })).status,'past_morning');
  assert.equal(calls,0);
});

test('B73: APNs refusal is a retry and a stale claimed device is skipped',async()=>{
  const repository=mockRepo([sha1,sha2]);
  repository.claim=async({subjectHash})=>
    subjectHash===sha2 ? null : {attempts:1,lockToken};
  const result=await dispatchDailyPalinsesto({repository,env,now:()=>now,
    fetchDailyFixtures:async()=>data,
    decrypt:()=> 'd'.repeat(64),
    send:async()=>({status:'rejected_by_apns',httpStatus:429}),
  });
  assert.equal(result.retry,1);
  assert.equal(result.skipped,1);
  assert.equal(repository.records[0].status,'retry');
});

test('B73: schema never shares registration or deliveries with automatic coupons',()=>{
  const sql=fs.readFileSync(path.join(__dirname,
    '../learning/migrations/b73_daily_palinsesto_push.sql'),'utf8');
  assert.match(sql,/sb_daily_palinsesto_subscriptions_v1/);
  assert.match(sql,/sb_daily_palinsesto_deliveries_v1/);
  assert.match(sql,/PRIMARY KEY \(subject_hash,local_day\)/);
  assert.doesNotMatch(sql,/DROP TABLE|TRUNCATE|sb_auto_coupon_|DELETE FROM/i);
});

test('B73: subscription upsert validates opt-in times and encrypted APNs fields',async()=>{
  const queries=[];
  const db=new DailyPalinsestoSubscriptionRepository({
    query:async (sql,args)=>{queries.push([sql,args]);return {rows:[],rowCount:1};},
  });
  await db.upsert({subjectHash:sha1,hour:8,minute:0,
    environment:'production',ciphertext:'abc',nonce:'def',authTag:'ghi'});
  assert.equal(queries.length,1);
  assert.match(queries[0][0],/ON CONFLICT \(subject_hash\)/);
  await assert.rejects(()=>db.upsert({subjectHash:sha1,hour:25,minute:0,
    environment:'production',ciphertext:'abc',nonce:'def',authTag:'ghi'}),/Invalid/);
  await db.unsubscribe(sha1);
  assert.match(queries[1][0],/DELETE FROM public.sb_daily_palinsesto_subscriptions_v1/);
});
