'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {validateGeneratedCoupon, officialMarketFamily} =
  require('../auto_coupon/daily_schedule');

const now = new Date('2026-11-09T08:10:00Z');
const preferences = {requested: true, hour: 8, minute: 0, events: 3,
  minimumMarketProbability: 65, market: 'MULTI', notifyChanges: true};
const events = [
  {fixtureId: 21, market: 'GOAL', marketProbability: 80,
    kickoffAt: '2026-11-09T19:30:00.000Z', odds: 1.42},
  {fixtureId: 22, market: 'NO GOAL', marketProbability: 70,
    kickoffAt: '2026-11-09T19:30:00.000Z', odds: 1.55},
  {fixtureId: 23, market: 'BTTS YES', marketProbability: 68,
    kickoffAt: '2026-11-09T19:30:00.000Z', odds: 1.70},
];
const coupon = arr => ({events: arr});
const validate = (arr, opts = {}) => validateGeneratedCoupon({
  coupon: coupon(arr), preferences: {...preferences, ...opts}, now,
});

test('exact European handicap quoted markets are supported only in MULTI', () => {
  const handicap = ['HCP EURO CASA -1 1', 'HCP EURO CASA +2 X', 'HCP EURO CASA 0 2'];
  for (const market of handicap) assert.equal(officialMarketFamily(market), 'HANDICAP_EUROPEAN');
  for (const invalid of ['HCP EURO CASA +6 1', 'HCP EURO CASA -1 1 EXTRA', 'HCP EURO CASA +1 1X']) {
    assert.equal(officialMarketFamily(invalid), null);
  }
  const coupon = {events: handicap.map((market, index) => ({
    fixtureId: 201 + index, market, marketProbability: 70,
    kickoffAt: '2026-11-09T19:30:00.000Z', odds: 1.70,
  }))};
  const prefs = {requested: true, hour: 8, minute: 0, events: 3,
    minimumMarketProbability: 65, market: 'MULTI', notifyChanges: true};
  assert.equal(validateGeneratedCoupon({coupon, preferences: prefs, now}).valid, true);
  assert.equal(validateGeneratedCoupon({coupon, preferences: {...prefs, market: '1X2'}, now}).reason, 'wrong_market');
  assert.equal(validateGeneratedCoupon({coupon: {events: coupon.events.map(e => ({...e, marketProbability: 64}))},
    preferences: prefs, now}).reason, 'below_probability_threshold');
});

test('actual Flutter market names resolve to the preference families', () => {
  for (const [market, family] of [
    ['1','1X2'], ['X','1X2'], ['2','1X2'],
    ['OVER 2.5','OVER_UNDER'], ['UNDER 1.5','OVER_UNDER'],
    ['GOAL','GOAL_NOGOAL'], ['NO GOAL','GOAL_NOGOAL'],
    ['BTTS YES','GOAL_NOGOAL'], ['BTTS NO','GOAL_NOGOAL'],
  ]) assert.equal(officialMarketFamily(market), family, market);
  assert.equal(officialMarketFamily('1X'), null);
  assert.equal(officialMarketFamily('CORRECT SCORE 1:0'), null);
});

test('real GOAL/NO GOAL outputs satisfy Goal category', () => {
  assert.equal(validate(events, {market:'GOAL_NOGOAL'}).valid, true);
});

test('real OVER 2.5 outputs satisfy Over/Under, never 1X2', () => {
  const over = events.map((e,i) => ({...e, market:i?'UNDER 2.5':'OVER 2.5'}));
  assert.equal(validate(over, {market:'OVER_UNDER'}).valid, true);
  assert.equal(validate(over, {market:'1X2'}).reason, 'wrong_market');
});

test('real 1/X/2 outputs satisfy 1X2 category', () => {
  const result = events.map((e,i) => ({...e, market:['1','X','2'][i]}));
  assert.equal(validate(result, {market:'1X2'}).valid, true);
});

test('mixed markets cannot pass single-family and missing real probability fails', () => {
  assert.equal(validate([{...events[0],market:'OVER 2.5'},...events.slice(1)],
    {market:'GOAL_NOGOAL'}).reason, 'wrong_market');
  assert.equal(validate(events.map((e,i)=>({...e,marketProbability:i?70:64})),
    {market:'GOAL_NOGOAL'}).reason, 'below_probability_threshold');
});
