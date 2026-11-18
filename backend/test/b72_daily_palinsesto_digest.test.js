'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {normalizeFixtureDigest,digestNotification,digestApnsPayload} =
  require('../daily_palinsesto/digest');

const localDay = '2026-11-21';
const now = new Date('2026-11-21T07:00:00Z'); // 08:00 Rome winter
const fixture = (id, name, leagueId, date, status='NS',country='Italia') => ({
  fixture:{id,date,status:{short:status}},
  league:{id:leagueId,name,country},
});
const feed = {response:[
  fixture(101,'Serie A',135,'2026-11-21T16:00:00Z'),
  fixture(102,'Serie A',135,'2026-11-21T19:45:00Z'),
  fixture(102,'Serie A',135,'2026-11-21T19:45:00Z'),
  fixture(103,'Premier League',39,'2026-11-21T12:30:00Z','NS','Inghilterra'),
  fixture(104,'LaLiga',140,'2026-11-21T20:00:00Z','NS','Spagna'),
  fixture(105,'Serie A',135,'2026-11-21T06:45:00Z'), // already started
  fixture(106,'Serie A',135,'2026-11-21T18:00:00Z','FT'),
  fixture(107,'Serie A',135,'2026-11-22T12:00:00Z'), // Sunday, not Saturday
  fixture(108,'Serie A',135,'2026-11-21T21:30:00Z','CANC'),
]};

test('B72: counts distinct future Saturday fixtures and actual leagues', () => {
  const digest=normalizeFixtureDigest(feed,{dayKey:localDay,now});
  assert.equal(digest.fixtureCount,4);
  assert.equal(digest.leagueCount,3);
  assert.deepEqual(digest.competitions.map(x=>[x.name,x.matches]),[
    ['Serie A',2],['Premier League',1],['LaLiga',1],
  ]);
  assert.equal(digest.meaning,'calendar_only_not_predictions_or_verified_bets');
});

test('B72: 8am Rome follows DST, never UTC calendar rollover', () => {
  const summerNow=new Date('2026-07-04T06:00:00Z');
  const digest=normalizeFixtureDigest({response:[
    fixture(200,'Bundesliga',78,'2026-07-04T21:30:00Z'),
    fixture(201,'Bundesliga',78,'2026-07-04T20:30:00Z'),
  ]},{dayKey:'2026-07-04',now:summerNow});
  assert.equal(digest.fixtureCount,1); // 20:30 UTC = 22:30 Rome
});

test('B72: malformed provider response is never reported as zero matches', () => {
  assert.throws(()=>normalizeFixtureDigest({errors:{requests:'rate limit'}},
    {dayKey:localDay,now}),/Invalid/);
  assert.throws(()=>normalizeFixtureDigest({response:null},
    {dayKey:localDay,now}),/Invalid/);
});

test('B72: notification truthfully says matches and leagues, not forecasts or odds', () => {
  const digest=normalizeFixtureDigest(feed,{dayKey:localDay,now});
  const notice=digestNotification(digest,{maxLeagues:2});
  assert.match(notice.body,/4 partite in 3 campionati/);
  assert.match(notice.body,/Serie A, Premier League e altri 1/);
  assert.doesNotMatch(notice.body,/affidabil|quota|vincente|schedina/i);
  const payload=JSON.parse(digestApnsPayload(digest));
  assert.equal(payload.kind,'daily_fixture_digest');
  assert.equal(payload.dayKey,localDay);
  assert.equal(payload.aps.alert.title,'GoalVdLine · Palinsesto di oggi');
  assert.ok(Buffer.byteLength(JSON.stringify(payload))<4096);
});

test('B72: no synthetic count when the day legitimately has no fixtures', () => {
  const digest=normalizeFixtureDigest({response:[]},{dayKey:localDay,now});
  assert.equal(digest.fixtureCount,0);
  assert.equal(digest.leagueCount,0);
  assert.equal(digestNotification(digest).body,
    'Nessuna partita futura nel calendario di oggi.');
});

test('B72: rejects invalid date and empty league or fixture identity', () => {
  assert.throws(()=>normalizeFixtureDigest(feed,{dayKey:'18-11-26',now}),/Invalid/);
  const digest=normalizeFixtureDigest({response:[
    fixture(0,'Serie A',135,'2026-11-21T16:00:00Z'),
    fixture(1,'',135,'2026-11-21T16:00:00Z'),
    fixture(2,'Serie A',-1,'2026-11-21T16:00:00Z'),
  ]},{dayKey:localDay,now});
  assert.equal(digest.fixtureCount,0);
});
