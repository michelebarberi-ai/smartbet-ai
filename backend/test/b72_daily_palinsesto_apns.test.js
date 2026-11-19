'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {digestPushReady,sendDailyPalinsestoPush}=
  require('../daily_palinsesto/apns_sender');

const privateKey=crypto.generateKeyPairSync('ec',{namedCurve:'prime256v1'})
  .privateKey.export({format:'pem',type:'pkcs8'}).toString();
const env={
  DAILY_PALINSESTO_PUSH_ENABLED:'true',
  APNS_KEY_ID:'ABCDEFGHIJ',APNS_TEAM_ID:'KLMNOPQRST',
  APNS_BUNDLE_ID:'com.example.goalvdline',
  APNS_ENVIRONMENT:'production',
  APNS_PRIVATE_KEY_BASE64:Buffer.from(privateKey).toString('base64'),
};
const token='abcd'.repeat(16);
const digest={
  dayKey:'2026-11-21',fixtureCount:14,leagueCount:3,
  competitions:[
    {leagueId:135,name:'Serie A',matches:7},
    {leagueId:39,name:'Premier League',matches:5},
    {leagueId:78,name:'Bundesliga',matches:2},
  ],
};

test('B72: daily push independent of automatic coupon worker flags',async()=>{
  assert.equal(digestPushReady({}),false);
  assert.equal(digestPushReady(env),true);
  assert.equal((await sendDailyPalinsestoPush({env:{},deviceToken:token,digest})).status,
    'disabled');
  assert.equal((await sendDailyPalinsestoPush({env,deviceToken:'bad',digest})).status,
    'invalid_device_token');
});

test('B72: signed APNs push contains only calendar counts and league names',async()=>{
  const result=await sendDailyPalinsestoPush({
    digest,deviceToken:token,env,now:()=>new Date('2026-11-21T07:00:00Z'),
    transport:async ({origin,headers,payload})=>{
      assert.equal(origin,'https://api.push.apple.com');
      assert.equal(headers[':path'],`/3/device/${token}`);
      assert.equal(headers['apns-topic'],env.APNS_BUNDLE_ID);
      assert.equal(headers['apns-collapse-id'],'palinsesto-2026-11-21');
      assert.equal(headers['apns-push-type'],'alert');
      assert.match(headers.authorization,/^bearer eyJ/);
      const msg=JSON.parse(payload);
      assert.equal(msg.kind,'daily_fixture_digest');
      assert.match(msg.aps.alert.body,/Serie A/);
      assert.match(msg.aps.alert.body,/14 partite in 3 campionati/);
      assert.doesNotMatch(JSON.stringify(msg),/quota|bookmaker|auto_coupon_ready/i);
      return {status:200};
    },
  });
  assert.equal(result.status,'accepted_by_apns');
});

test('B72: APNs errors do not leak tokens or sensitive data',async()=>{
  assert.equal((await sendDailyPalinsestoPush({
    digest,deviceToken:token,env,transport:async()=>({status:410}),
  })).status,'unregistered_device');
  assert.deepEqual(await sendDailyPalinsestoPush({
    digest,deviceToken:token,env,transport:async()=>({status:403}),
  }),{status:'rejected_by_apns',httpStatus:403});
  assert.equal((await sendDailyPalinsestoPush({
    digest,deviceToken:token,env,transport:async()=>{throw Error('private token');},
  })).status,'transport_error');
});
