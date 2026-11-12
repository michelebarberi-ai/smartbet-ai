'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {validatePreferences, validateGeneratedCoupon, allowedRomeDays} =
  require('../auto_coupon/daily_schedule');
const {futureCoupon} = require('../auto_coupon/push_dispatch');

const now = new Date('2026-11-12T10:00:00.000Z');
const prefs = {requested:true,hour:8,minute:0,events:3,
  minimumMarketProbability:65,market:'MULTI',notifyChanges:false,
  systemMode:'THREE_SAME_FIXTURES'};
const kickoff = ['2026-11-12T19:00:00.000Z',
  '2026-11-13T19:00:00.000Z','2026-11-14T19:00:00.000Z'];
function coupon() {
  const primary = kickoff.map((time, i) => ({fixtureId:i+10,
    market:'OVER 1.5',marketProbability:70,kickoffAt:time,odds:1.5}));
  return {windowDays:3,events:primary,coupons:[
    {name:'PRINCIPALE',events:primary},
    {name:'ALTERNATIVA_1',events:primary.map((e,i) =>
      i===0?{...e,market:'GOAL'}:e)},
    {name:'ALTERNATIVA_2',events:primary.map((e,i) =>
      i===1?{...e,market:'UNDER 2.5'}:e)},
  ]};
}
test('P20.4 legacy preferences stay on current Rome day',()=>{
  assert.equal(validatePreferences(prefs),true);
  assert.equal(validatePreferences({...prefs,windowDays:1}),true);
  assert.equal(validateGeneratedCoupon({coupon:coupon(),
    preferences:prefs,now}).reason,'invalid_or_out_of_day_kickoff');
});
test('P20.4 only 1, 2 or 3 calendar days are accepted',()=>{
  for(const n of [0,4,-1,1.5,'2',null]) {
    assert.equal(validatePreferences({...prefs,windowDays:n}),false);
  }
  for(const n of [1,2,3]) assert.equal(validatePreferences({...prefs,windowDays:n}),true);
});
test('P20.4 three coordinated slips can span today, tomorrow and next day',()=>{
  const result=validateGeneratedCoupon({coupon:coupon(),
    preferences:{...prefs,windowDays:3},now});
  assert.deepEqual(result,{valid:true,dayKey:'2026-11-12'});
  assert.equal(futureCoupon(coupon(),'2026-11-12',now),true);
});
test('P20.4 shorter window and mismatched official declaration fail closed',()=>{
  const c=coupon();
  assert.equal(validateGeneratedCoupon({coupon:c,
    preferences:{...prefs,windowDays:2},now}).reason,'invalid_or_out_of_day_kickoff');
  c.events[2].kickoffAt='2026-11-13T20:00:00.000Z';
  c.coupons.forEach(v=>{v.events=v.events.map((e,i)=>i===2?{...e,kickoffAt:c.events[2].kickoffAt}:e)});
  assert.equal(validateGeneratedCoupon({coupon:c,
    preferences:{...prefs,windowDays:2},now}).reason,'window_mismatch');
});
test('P20.4 future dates beyond 3 calendar days are refused',()=>{
  const c=coupon();
  c.events[2].kickoffAt='2026-11-15T19:00:00.000Z';
  c.coupons.forEach(v=>{v.events=v.events.map((e,i)=>i===2?{...e,kickoffAt:c.events[2].kickoffAt}:e)});
  assert.equal(validateGeneratedCoupon({coupon:c,
    preferences:{...prefs,windowDays:3},now}).reason,'invalid_or_out_of_day_kickoff');
  assert.equal(futureCoupon(c,'2026-11-12',now),false);
});
test('P20.4 push rejects a coupon after its scheduling day',()=>{
  assert.equal(futureCoupon(coupon(),'2026-11-12',
    new Date('2026-11-13T10:00:00.000Z')),false);
});
test('P20.4 Europe/Rome DST transition uses calendar dates',()=>{
  const days = allowedRomeDays(new Date('2027-03-27T23:30:00.000Z'),3);
  assert.deepEqual([...days], ['2027-03-28','2027-03-29','2027-03-30']);
  assert.deepEqual([...allowedRomeDays(new Date('2027-10-30T23:30:00.000Z'),3)],
    ['2027-10-31','2027-11-01','2027-11-02']);
});
