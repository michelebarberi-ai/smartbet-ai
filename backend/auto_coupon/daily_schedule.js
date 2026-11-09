'use strict';

// Fase P6: logica deterministica del calendario AutoSchedina.
// Nessun timer, invio push o generazione partite viene avviato da questo modulo.
// Un worker esterno con storage persistente dovra' chiamarlo in modo periodico.

const DEFAULT_TIME_ZONE = 'Europe/Rome';
const ALLOWED_MARKETS = new Set(['MULTI', 'OVER_UNDER', 'GOAL_NOGOAL', '1X2']);

function validatePreferences(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const integerIn = (v, min, max) => Number.isInteger(v) && v >= min && v <= max;
  return typeof value.requested === 'boolean' &&
    integerIn(value.hour, 0, 23) &&
    integerIn(value.minute, 0, 59) &&
    integerIn(value.events, 3, 6) &&
    integerIn(value.minimumMarketProbability, 50, 90) &&
    value.minimumMarketProbability % 5 === 0 &&
    ALLOWED_MARKETS.has(value.market) &&
    typeof value.notifyChanges === 'boolean';
}

function localClock(instant, timeZone = DEFAULT_TIME_ZONE) {
  if (!(instant instanceof Date) || !Number.isFinite(instant.getTime())) {
    throw new TypeError('Invalid instant');
  }
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(instant);
  const values = Object.fromEntries(parts.map(({type, value}) => [type, value]));
  return {
    dayKey: `${values.year}-${values.month}-${values.day}`,
    minutesSinceMidnight: Number(values.hour) * 60 + Number(values.minute),
  };
}

/**
 * A daily run is due once the configured local wall clock time has passed.
 * lastGeneratedDay MUST be read from durable server storage and protected by
 * a unique (client, dayKey) constraint; this function alone is not a lock.
 */
function dailyRunStatus({preferences, now = new Date(), lastGeneratedDay = null,
  timeZone = DEFAULT_TIME_ZONE} = {}) {
  if (!validatePreferences(preferences)) return {due: false, reason: 'invalid_preferences'};
  if (!preferences.requested) return {due: false, reason: 'disabled'};
  const {dayKey, minutesSinceMidnight} = localClock(now, timeZone);
  if (lastGeneratedDay === dayKey) return {due: false, reason: 'already_generated', dayKey};
  const startMinute = preferences.hour * 60 + preferences.minute;
  if (minutesSinceMidnight < startMinute) return {due: false, reason: 'before_scheduled_time', dayKey};
  return {due: true, dayKey};
}

/**
 * Validation of an already-generated coupon. Selection and ranking MUST be
 * delegated to the same official engine used by the app, not recreated here.
 * Every selection must be for a unique future fixture on the local day, with
 * an explicit finite market probability and no guessed odds.
 */
function validateGeneratedCoupon({coupon, preferences, now = new Date(),
  timeZone = DEFAULT_TIME_ZONE} = {}) {
  if (!validatePreferences(preferences) || !coupon || !Array.isArray(coupon.events)) {
    return {valid: false, reason: 'invalid_input'};
  }
  if (coupon.events.length !== preferences.events) {
    return {valid: false, reason: 'insufficient_events'};
  }
  const scheduledDay = localClock(now, timeZone).dayKey;
  const uniqueFixtures = new Set();
  for (const event of coupon.events) {
    if (!event || !Number.isSafeInteger(event.fixtureId) || event.fixtureId <= 0 ||
        uniqueFixtures.has(event.fixtureId)) {
      return {valid: false, reason: 'invalid_or_duplicate_fixture'};
    }
    uniqueFixtures.add(event.fixtureId);
    if (typeof event.market !== 'string' || !event.market.trim()) {
      return {valid: false, reason: 'missing_market'};
    }
    if (preferences.market !== 'MULTI' && event.market !== preferences.market) {
      return {valid: false, reason: 'wrong_market'};
    }
    if (typeof event.marketProbability !== 'number' ||
        !Number.isFinite(event.marketProbability) ||
        event.marketProbability < preferences.minimumMarketProbability ||
        event.marketProbability > 100) {
      return {valid: false, reason: 'below_probability_threshold'};
    }
    if (typeof event.kickoffAt !== 'string') {
      return {valid: false, reason: 'missing_kickoff'};
    }
    const kickoff = new Date(event.kickoffAt);
    if (!Number.isFinite(kickoff.getTime()) || kickoff <= now ||
        localClock(kickoff, timeZone).dayKey !== scheduledDay) {
      return {valid: false, reason: 'invalid_or_out_of_day_kickoff'};
    }
    if ('odds' in event && (typeof event.odds !== 'number' ||
        !Number.isFinite(event.odds) || event.odds <= 1)) {
      return {valid: false, reason: 'invalid_odds'};
    }
  }
  return {valid: true, dayKey: scheduledDay};
}

module.exports = {DEFAULT_TIME_ZONE, validatePreferences, localClock,
  dailyRunStatus, validateGeneratedCoupon};
