'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  localClock, validatePreferences, dailyRunStatus, validateGeneratedCoupon,
} = require('../auto_coupon/daily_schedule');

const config = {
  requested: true, hour: 8, minute: 0, events: 3,
  minimumMarketProbability: 65, market: 'MULTI', notifyChanges: true,
};
const at = iso => new Date(iso);
const now = at('2026-11-09T08:00:00Z'); // Rome 09:00
const validCoupon = () => ({events: [1, 2, 3].map(fixtureId => ({
  fixtureId, market: '1X2', marketProbability: 70,
  kickoffAt: '2026-11-09T19:00:00Z', odds: 1.7,
}))});

test('validates exact mobile preferences contract', () => {
  assert.equal(validatePreferences(config), true);
  assert.equal(validatePreferences({...config, hour: 24}), false);
  assert.equal(validatePreferences({...config, minute: 60}), false);
  assert.equal(validatePreferences({...config, minimumMarketProbability: 63}), false);
  assert.equal(validatePreferences({...config, events: 16}), false);
  assert.equal(validatePreferences({...config, market: 'UNKNOWN'}), false);
  assert.equal(validatePreferences({...config, requested: 'yes'}), false);
});

test('runs only after local scheduled time, not UTC time', () => {
  assert.equal(dailyRunStatus({preferences: config, now: at('2026-11-09T06:59:00Z')}).due, false);
  assert.equal(dailyRunStatus({preferences: config, now: at('2026-11-09T07:00:00Z')}).due, true);
});

test('respects Rome summer time without a fixed UTC offset', () => {
  assert.equal(localClock(at('2026-07-10T06:00:00Z')).minutesSinceMidnight, 8 * 60);
  assert.equal(localClock(at('2026-01-10T07:00:00Z')).minutesSinceMidnight, 8 * 60);
});

test('does not create a second coupon on the same local day', () => {
  assert.equal(dailyRunStatus({preferences: config, now, lastGeneratedDay: '2026-11-09'}).reason,
    'already_generated');
});

test('disabled schedule is not due', () => {
  assert.equal(dailyRunStatus({preferences: {...config, requested: false}, now}).reason, 'disabled');
});

test('rejects invalid schedule and invalid instant', () => {
  assert.equal(dailyRunStatus({preferences: {...config, events: 0}, now}).reason,
    'invalid_preferences');
  assert.throws(() => localClock(new Date(NaN)), TypeError);
});

test('accepts validated official engine coupon', () => {
  assert.equal(validateGeneratedCoupon({coupon: validCoupon(), preferences: config, now}).valid, true);
});

test('rejects under-threshold prediction', () => {
  const coupon = validCoupon();
  coupon.events[2].marketProbability = 64;
  assert.equal(validateGeneratedCoupon({coupon, preferences: config, now}).reason,
    'below_probability_threshold');
});

test('rejects duplicate fixtures', () => {
  const coupon = validCoupon();
  coupon.events[2].fixtureId = 1;
  assert.equal(validateGeneratedCoupon({coupon, preferences: config, now}).reason,
    'invalid_or_duplicate_fixture');
});

test('rejects incomplete coupon instead of inventing events', () => {
  const coupon = validCoupon();
  coupon.events.pop();
  assert.equal(validateGeneratedCoupon({coupon, preferences: config, now}).reason,
    'insufficient_events');
});

test('rejects past fixture and fixtures on following day', () => {
  const coupon = validCoupon();
  coupon.events[0].kickoffAt = '2026-11-08T19:00:00Z';
  assert.equal(validateGeneratedCoupon({coupon, preferences: config, now}).reason,
    'invalid_or_out_of_day_kickoff');
  coupon.events[0].kickoffAt = '2026-11-10T19:00:00Z';
  assert.equal(validateGeneratedCoupon({coupon, preferences: config, now}).reason,
    'invalid_or_out_of_day_kickoff');
});

test('rejects missing or invalid odds, when provided', () => {
  const coupon = validCoupon();
  coupon.events[0].odds = Infinity;
  assert.equal(validateGeneratedCoupon({coupon, preferences: config, now}).reason, 'invalid_odds');
});

test('rejects cross-family markets under a single-market schedule', () => {
  assert.equal(validateGeneratedCoupon({coupon: validCoupon(),
    preferences: {...config, market: 'GOAL_NOGOAL'}, now}).reason, 'wrong_market');
});

test('rejects NaN probability and missing kickoff', () => {
  const coupon = validCoupon();
  coupon.events[0].marketProbability = NaN;
  assert.equal(validateGeneratedCoupon({coupon, preferences: config, now}).reason,
    'below_probability_threshold');
  coupon.events[0].marketProbability = 80;
  delete coupon.events[0].kickoffAt;
  assert.equal(validateGeneratedCoupon({coupon, preferences: config, now}).reason,
    'missing_kickoff');
});
