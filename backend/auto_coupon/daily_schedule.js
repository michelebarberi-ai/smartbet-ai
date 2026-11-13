'use strict';

// Fase P6: logica deterministica del calendario AutoSchedina.
// Nessun timer, invio push o generazione partite viene avviato da questo modulo.
// Un worker esterno con storage persistente dovra' chiamarlo in modo periodico.

const DEFAULT_TIME_ZONE = 'Europe/Rome';
const ALLOWED_MARKETS = new Set(['MULTI', 'OVER_UNDER', 'GOAL_NOGOAL', '1X2']);
const THREE_MODE = 'THREE_SAME_FIXTURES';
const SINGLE_MODE = 'SINGLE';
const OR_MARKETS = new Set([
  'GOAL O OVER 1.5', 'GOAL O OVER 2.5',
  '1X O OVER 1.5', '1X O OVER 2.5',
  'X O OVER 1.5', 'X O OVER 2.5',
  '1 O OVER 1.5', '1 O OVER 2.5',
  'X O UNDER 2.5', 'X O UNDER 3.5',
  '2 O UNDER 2.5', '2 O UNDER 3.5',
  '1X O UNDER 2.5', '1X O UNDER 3.5',
]);

function validatePreferences(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const integerIn = (v, min, max) => Number.isInteger(v) && v >= min && v <= max;
  return typeof value.requested === 'boolean' &&
    integerIn(value.hour, 0, 23) &&
    integerIn(value.minute, 0, 59) &&
    integerIn(value.events, 3, 15) &&
    integerIn(value.minimumMarketProbability, 50, 90) &&
    value.minimumMarketProbability % 5 === 0 &&
    (value.windowDays === undefined || integerIn(value.windowDays, 1, 3)) &&
    ALLOWED_MARKETS.has(value.market) &&
    typeof value.notifyChanges === 'boolean' &&
    (value.systemMode === undefined || value.systemMode === SINGLE_MODE ||
      value.systemMode === THREE_MODE);
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
 * Calendar days (rather than 24-hour durations) handle Rome DST changes.
 * The schedule is still claimed once per generation day, not per fixture day.
 */
function allowedRomeDays(now, windowDays = 1, timeZone = DEFAULT_TIME_ZONE) {
  if (!Number.isInteger(windowDays) || windowDays < 1 || windowDays > 3) {
    throw new RangeError('Invalid coupon day window');
  }
  const [year, month, day] = localClock(now, timeZone).dayKey.split('-').map(Number);
  return new Set(Array.from({length: windowDays}, (_, offset) =>
    new Date(Date.UTC(year, month - 1, day + offset)).toISOString().slice(0, 10)));
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
/**
 * Convert the exact markets emitted by Flutter SmartBetSportsMarketPick into
 * the user's preference families.  A preference is never an event/outcome.
 * Prior clients also used category labels in mock tests; these are accepted
 * for backwards-compatible validation but NOT produced by the Flutter export.
 */
function officialMarketFamily(value) {
  if (typeof value !== 'string') return null;
  const market = value.trim().toUpperCase().replace(/\s+/g, ' ').replace(/,/g, '.');
  if (/^(?:OVER|UNDER) ?\d+(?:\.\d+)?$/.test(market) || market === 'OVER_UNDER') {
    return 'OVER_UNDER';
  }
  if (/^(?:GOAL|NO GOAL|NOGOAL|BTTS YES|BTTS NO)$/.test(market) ||
      market === 'GOAL_NOGOAL') return 'GOAL_NOGOAL';
  if (/^(?:1|X|2|1X2)$/.test(market)) return '1X2';
  if (OR_MARKETS.has(market)) return 'OR';
  // Exact official football-market key; not a synthetic handicap.
  if (/^HCP EURO CASA [+-]?[0-5] [1X2]$/.test(market)) return 'HANDICAP_EUROPEAN';
  return null;
}

function validateSingleCoupon({coupon, preferences, now, timeZone}) {
  if (!validatePreferences(preferences) || !coupon || !Array.isArray(coupon.events)) {
    return {valid: false, reason: 'invalid_input'};
  }
  if (coupon.events.length !== preferences.events) {
    return {valid: false, reason: 'insufficient_events'};
  }
  const scheduledDay = localClock(now, timeZone).dayKey;
  const allowedDays = allowedRomeDays(now, preferences.windowDays ?? 1, timeZone);
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
    const family = officialMarketFamily(event.market);
    if (!family || (preferences.market !== 'MULTI' &&
        family !== preferences.market)) {
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
        !allowedDays.has(localClock(kickoff, timeZone).dayKey)) {
      return {valid: false, reason: 'invalid_or_out_of_day_kickoff'};
    }
    if (event.bookmaker !== undefined &&
        (typeof event.bookmaker !== 'string' ||
          !event.bookmaker.trim() || event.bookmaker.length > 80 ||
          ['n/d','unknown','sconosciuto','n.a.'].includes(
            event.bookmaker.trim().toLowerCase()))) {
      return {valid:false,reason:'invalid_bookmaker'};
    }
    if ('odds' in event && (typeof event.odds !== 'number' ||
        !Number.isFinite(event.odds) || event.odds < 1.20)) {
      // Triple slips use a distinct reason; SINGLE retains the legacy
      // invalid-optional-odds classification.
      return {valid: false, reason: preferences.systemMode === THREE_MODE
        ? 'missing_or_low_triple_odds' : 'invalid_odds'};
    }
    // All three coordinated variants must have genuine quoted odds.
    // Legacy SINGLE keeps its backward-compatible optional-odds contract.
    if (preferences.systemMode === THREE_MODE &&
        (!Object.hasOwn(event, 'odds') || event.odds < 1.20)) {
      return {valid: false, reason: 'missing_or_low_triple_odds'};
    }
  }
  return {valid: true, dayKey: scheduledDay};
}


/** Three distinct slips, exactly the same ordered fixtures and kickoffs.
 *  The first slip also remains in coupon.events for old readers.
 *  Server verifies claims but cannot manufacture predictions.
 */
function validateGeneratedCoupon({coupon, preferences, now = new Date(),
  timeZone = DEFAULT_TIME_ZONE} = {}) {
  const first = validateSingleCoupon({coupon, preferences, now, timeZone});
  if (!first.valid) return first;
  // A wider date window must be explicitly certified by the official engine.
  if ((coupon.windowDays ?? 1) !== (preferences.windowDays ?? 1)) {
    return {valid: false, reason: 'window_mismatch'};
  }
  if (preferences.systemMode !== THREE_MODE) {
    if (coupon.coupons !== undefined) return {valid:false, reason:'unexpected_variants'};
    return first;
  }
  if (!Array.isArray(coupon.coupons) || coupon.coupons.length !== 3) {
    return {valid:false, reason:'missing_three_coupons'};
  }
  const signatures = new Set();
  const primary = coupon.events;
  for (let index = 0; index < 3; index++) {
    const variant = coupon.coupons[index];
    if (!variant || typeof variant !== 'object' ||
        !Array.isArray(variant.events) ||
        typeof variant.name !== 'string' || !/^(PRINCIPALE|ALTERNATIVA_1|ALTERNATIVA_2)$/.test(variant.name) ||
        variant.name !== ['PRINCIPALE','ALTERNATIVA_1','ALTERNATIVA_2'][index]) {
      return {valid:false, reason:'invalid_variant'};
    }
    const status = validateSingleCoupon({coupon:variant,preferences,now,timeZone});
    if (!status.valid) return status;
    for (let i=0;i<primary.length;i++) {
      const original = primary[i], current = variant.events[i];
      if (original.fixtureId !== current.fixtureId ||
          original.kickoffAt !== current.kickoffAt) {
        return {valid:false,reason:'variants_different_fixtures'};
      }
      if (index===0 && (original.market!==current.market ||
          original.marketProbability!==current.marketProbability ||
          original.odds!==current.odds)) {
        return {valid:false,reason:'primary_variant_mismatch'};
      }
    }
    signatures.add(variant.events.map(e=>`${e.fixtureId}/${e.market}`).join('|'));
  }
  if (signatures.size!==3) return {valid:false,reason:'variants_not_distinct'};
  return first;
}

module.exports = {DEFAULT_TIME_ZONE, validatePreferences, localClock, allowedRomeDays,
  dailyRunStatus, validateGeneratedCoupon, officialMarketFamily};
