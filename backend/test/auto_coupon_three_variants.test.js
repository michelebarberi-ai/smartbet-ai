'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {validatePreferences,validateGeneratedCoupon}=require('../auto_coupon/daily_schedule');
const {AutoCouponGenerationCoordinator}=require('../auto_coupon/generation_coordinator');
const {futureCoupon}=require('../auto_coupon/push_dispatch');
const NOW=new Date('2026-11-09T09:00:00.000Z');
const PREF={requested:true,hour:8,minute:0,events:3,minimumMarketProbability:65,
  market:'MULTI',notifyChanges:true,systemMode:'THREE_SAME_FIXTURES'};
const event=(i,market='OVER 1.5')=>({fixtureId:i,market,marketProbability:74,
  kickoffAt:'2026-11-09T19:00:00.000Z',odds:1.7});
const create=(count=3)=>{
  const first=Array.from({length:count},(_,i)=>event(i+1));
  const second=first.map((x,i)=>({...x,market:i===0?'GOAL':x.market}));
  const third=first.map((x,i)=>({...x,market:i===1?'UNDER 2.5':x.market}));
  return {events:first,coupons:[
    {name:'PRINCIPALE',events:first},
    {name:'ALTERNATIVA_1',events:second},
    {name:'ALTERNATIVA_2',events:third},
  ]};
};
const check=(coupon,prefs=PREF)=>validateGeneratedCoupon({coupon,preferences:prefs,now:NOW});

test('P20 accepts 3..15 events, only explicit valid modes',()=>{
  assert.equal(validatePreferences(PREF),true);
  assert.equal(validatePreferences({...PREF,events:15}),true);
  assert.equal(validatePreferences({...PREF,events:16}),false);
  assert.equal(validatePreferences({...PREF,events:2}),false);
  assert.equal(validatePreferences({...PREF,systemMode:'UNKNOWN'}),false);
  assert.equal(validatePreferences({...PREF,systemMode:'SINGLE'}),true);
  assert.equal(validatePreferences({...PREF,systemMode:undefined}),true);
});

test('P20 validates three distinct same-fixture coupons, including 15 events',()=>{
  assert.deepEqual(check(create()),{valid:true,dayKey:'2026-11-09'});
  assert.equal(check(create(15),{...PREF,events:15}).valid,true);
});

test('P20 rejects no variants, duplicates, changed fixture/date, below threshold',()=>{
  const single=create(); delete single.coupons;
  assert.equal(check(single).reason,'missing_three_coupons');
  const duplicate=create(); duplicate.coupons[2].events=duplicate.coupons[1].events;
  assert.equal(check(duplicate).reason,'variants_not_distinct');
  const changed=create(); changed.coupons[1].events[0].fixtureId=999;
  assert.equal(check(changed).reason,'variants_different_fixtures');
  const date=create();date.coupons[1].events[0].kickoffAt='2026-11-09T20:00:00.000Z';
  assert.equal(check(date).reason,'variants_different_fixtures');
  const weak=create();weak.coupons[1].events[0].marketProbability=64;
  assert.equal(check(weak).reason,'below_probability_threshold');
  const mismatch=create();mismatch.coupons[0].events=mismatch.coupons[0].events.map(x=>({...x}));
  mismatch.coupons[0].events[0].odds=2.3;
  assert.equal(check(mismatch).reason,'primary_variant_mismatch');
  const wrongFamily=create();wrongFamily.coupons[1].events[0].market='GOAL';
  assert.equal(check(wrongFamily,{...PREF,market:'OVER_UNDER'}).reason,'wrong_market');
});

test('P20 legacy single without mode works, but triple not accepted without mode',()=>{
  const prefs={...PREF};delete prefs.systemMode;
  assert.equal(check({events:create().events},prefs).valid,true);
  assert.equal(check(create(),prefs).reason,'unexpected_variants');
});

test('P20 coordinator saves sanitized three-coupon bundle, one daily claim',async()=>{
  const stored=[];
  const repo={async initialize(){},async claimAutoCouponRun(){return {attempts:1}},
    async finishAutoCouponRun(v){stored.push(v);return true;}};
  const coordinator=new AutoCouponGenerationCoordinator({repository:repo,
    now:()=>NOW,generateOfficialCoupon:async()=>({...create(),secrets:'not stored'})});
  const result=await coordinator.runOne({subjectHash:'a'.repeat(64),preferences:PREF});
  assert.equal(result.status,'ready');
  assert.equal(stored[0].coupon.coupons.length,3);
  assert.equal(stored[0].coupon.events.length,3);
  assert.equal(JSON.stringify(stored).includes('secrets'),false);
});

test('P20 push eligibility checks all three coupons and up to 15',()=>{
  assert.equal(futureCoupon(create(15),'2026-11-09',NOW),true);
  const bad=create();bad.coupons[1].events[1].fixtureId=111;
  assert.equal(futureCoupon(bad,'2026-11-09',NOW),false);
});
