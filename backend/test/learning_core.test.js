'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isSupportedMarket, settleMarket, normalizeMarket, fixtureBeforeKickoff,
  finishedScore, validateBatch, hashClientId, validToken,
} = require('../learning/learning_core');

const uuid = 'a7c2b3d4-1111-4111-8111-eeee12345678';
const match = (date, status='NS', fixtureId=10, score=null) => ({response: [{
  fixture: {id:fixtureId, date, status: {short:status}},
  goals: score, score: {fulltime: score},
}]});

test('normalizes and restricts markets', () => {
  assert.equal(normalizeMarket('  over  2.5  '), 'OVER 2.5');
  for (const m of ['1','X2','GOAL','OVER 2.5','UNDER 1.5','CASA 2+ GOL',
    'HCP EURO CASA -2 2','1X + O1.5','MULTIGOL 2-4']) assert.equal(isSupportedMarket(m), true, m);
  for (const m of ['COMBO CHANCE','CORNER 1','UNDER 2','HCP ASIA CASA -1',
    'CASA SEGNA PRIMA','MULTIGOL 5-2','OVER 100.5','1X + IMPOSSIBLE']) {
    assert.equal(isSupportedMarket(m), false, m);
  }
});

test('settles 1X2 and double chance', () => {
  assert.equal(settleMarket('1', 2, 0), true);
  assert.equal(settleMarket('1', 0, 2), false);
  assert.equal(settleMarket('X', 2, 2), true);
  assert.equal(settleMarket('1X', 1, 1), true);
  assert.equal(settleMarket('12', 1, 1), false);
});

test('settles over/under and both teams score', () => {
  assert.equal(settleMarket('OVER 2.5', 2, 1), true);
  assert.equal(settleMarket('UNDER 2.5', 2, 1), false);
  assert.equal(settleMarket('GOAL', 2, 1), true);
  assert.equal(settleMarket('NO GOAL', 2, 0), true);
  assert.equal(settleMarket('CASA 3+ GOL', 3, 1), true);
});

test('settles European handicap exactly as Dart', () => {
  assert.equal(settleMarket('HCP EURO CASA -2 2', 0, 0), true);
  assert.equal(settleMarket('HCP EURO CASA -2 X', 2, 0), true);
  assert.equal(settleMarket('HCP EURO CASA -2 1', 3, 0), true);
  assert.equal(settleMarket('HCP EURO CASA -2 1', 1, 0), false);
});

test('settles compound markets and multigol', () => {
  assert.equal(settleMarket('1X + O1.5', 2, 1), true);
  assert.equal(settleMarket('X2 + U2.5', 0, 1), true);
  assert.equal(settleMarket('X2 + U2.5', 3, 1), false);
  assert.equal(settleMarket('CASA 2+ GOL', 2, 1), true);
  assert.equal(settleMarket('MULTIGOL 2-4', 3, 1), true);
  assert.equal(settleMarket('MULTIGOL 2-4', 4, 1), false);
});

test('rejects invalid score or unknown markets', () => {
  assert.equal(settleMarket('CORNER CASA', 2, 1), null);
  assert.equal(settleMarket('1', -1, 2), null);
});

test('accepts only verified future kickoff', () => {
  const now = new Date('2026-11-01T12:00:00Z');
  assert.ok(fixtureBeforeKickoff(match('2026-11-01T13:00:00Z'), now));
  assert.equal(fixtureBeforeKickoff(match('2026-11-01T11:00:00Z'), now), null);
  assert.equal(fixtureBeforeKickoff(match('2026-11-01T13:00:00Z','1H'), now), null);
  assert.equal(fixtureBeforeKickoff(match('invalid'), now), null);
  assert.equal(fixtureBeforeKickoff(match('2026-11-01T12:01:00Z'), now), null);
});

test('handles FT and extra time with regulation-only scores', () => {
  assert.deepEqual(finishedScore(match('2026-11-01','FT',10,{home:2,away:1})), {home:2,away:1});
  assert.deepEqual(finishedScore(match('2026-11-01','AET',10,{home:1,away:1})), {home:1,away:1});
  assert.equal(finishedScore(match('2026-11-01','1H',10,{home:0,away:0})), null);
  assert.equal(finishedScore(match('2026-11-01','AWD',10,{home:3,away:0})), null);
});

test('validates payloads and reject duplicates/unsupported markets', () => {
  const pred = {fixtureId:10, engine:'smartBet', market:'over 2.5', probability:0.8};
  assert.deepEqual(validateBatch({clientId:uuid,predictions:[pred]}).predictions[0],
    {...pred,market:'OVER 2.5'});
  assert.equal(validateBatch({clientId:'email@example.com',predictions:[pred]}),null);
  assert.equal(validateBatch({clientId:uuid,predictions:[pred,pred]}),null);
  assert.equal(validateBatch({clientId:uuid,predictions:[{...pred,probability:1.1}]}),null);
  assert.equal(validateBatch({clientId:uuid,predictions:[{...pred,market:'CORNER'}]}),null);
  assert.equal(validateBatch({clientId:uuid,predictions:Array(21).fill(pred)}),null);
});

test('client identifiers stored as salted hashes; admin token time-safe', () => {
  assert.notEqual(hashClientId(uuid, 'salt-one'), hashClientId(uuid, 'salt-two'));
  assert.equal(hashClientId(uuid, 'salt-one').length,64);
  assert.equal(validToken('abc','abc'),true);
  assert.equal(validToken('abc','abd'),false);
  assert.equal(validToken('a','abc'),false);
  assert.equal(validToken(undefined,'abc'),false);
});
