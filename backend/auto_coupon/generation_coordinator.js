'use strict';

// B45 P8: server-side orchestration, never a replacement for the official
// Flutter coupon ranking engine. This module does nothing until an external
// worker explicitly calls it with a verified, equivalent official generator.
const {dailyRunStatus, validateGeneratedCoupon} = require('./daily_schedule');

const SUBJECT_HASH = /^[0-9a-f]{64}$/;
const MAX_BATCH = 100;

function publicEvents(events) {
  return events.map(event => ({
    fixtureId: event.fixtureId,
    market: event.market,
    marketProbability: event.marketProbability,
    kickoffAt: event.kickoffAt,
    ...(Object.hasOwn(event, 'odds') ? {odds: event.odds} : {}),
  }));
}
function publicCoupon(coupon) {
  const events = publicEvents(coupon.events);
  if (!coupon.coupons) return {events};
  return {events, coupons:coupon.coupons.map(({name,events}) => ({
    name, events:publicEvents(events),
  }))};
}

class AutoCouponGenerationCoordinator {
  constructor({repository, generateOfficialCoupon = null, now = () => new Date()}) {
    this.repository = repository;
    this.generateOfficialCoupon = generateOfficialCoupon;
    this.now = now;
  }

  async runOne({subjectHash, preferences}) {
    if (!SUBJECT_HASH.test(subjectHash || '')) {
      return {status: 'invalid_subject'};
    }
    const now = this.now();
    const due = dailyRunStatus({preferences, now});
    if (!due.due) return {status: 'skipped', reason: due.reason};

    // Fail closed. No guessed, mock or independently recalculated predictions.
    if (typeof this.generateOfficialCoupon !== 'function') {
      return {status: 'official_engine_not_connected'};
    }

    await this.repository.initialize();
    const claim = await this.repository.claimAutoCouponRun({
      subjectHash, dayKey: due.dayKey, now,
    });
    if (!claim) return {status: 'already_claimed_or_not_due'};

    let proposed;
    try {
      proposed = await this.generateOfficialCoupon({
        subjectHash, dayKey: due.dayKey, preferences, now,
      });
    } catch (_) {
      // No provider exception details, secrets, or partial coupons are persisted.
      const completed = await this.repository.finishAutoCouponRun({
        subjectHash, dayKey: due.dayKey, attempts: claim.attempts,
        outcome: 'retry', reason: 'provider_unavailable', now,
        retryMinutes: 15,
      });
      return completed ? {status: 'retry', reason: 'provider_unavailable'} :
        {status: 'superseded'};
    }
    const validation = validateGeneratedCoupon({coupon: proposed, preferences, now});
    if (!validation.valid || validation.dayKey !== due.dayKey) {
      const completed = await this.repository.finishAutoCouponRun({
        subjectHash, dayKey: due.dayKey, attempts: claim.attempts,
        outcome: 'retry', reason: 'insufficient_events', now,
        retryMinutes: 60,
      });
      return completed ? {status: 'retry', reason: 'insufficient_events'} :
        {status: 'superseded'};
    }
    const coupon = publicCoupon(proposed);
    const completed = await this.repository.finishAutoCouponRun({
      subjectHash, dayKey: due.dayKey, attempts: claim.attempts,
      outcome: 'ready', coupon, now,
    });
    return {status: completed ? 'ready' : 'superseded', dayKey: due.dayKey};
  }

  // Explicitly invoked by a future authenticated scheduled worker; no timer.
  async runBatch({limit = MAX_BATCH, afterSubjectHash = null} = {}) {
    if (typeof this.generateOfficialCoupon !== 'function') {
      return {status: 'official_engine_not_connected', checked: 0};
    }
    if (!Number.isInteger(limit) || limit < 1 || limit > MAX_BATCH ||
        (afterSubjectHash !== null && !SUBJECT_HASH.test(afterSubjectHash))) {
      throw new RangeError('Invalid batch limit');
    }
    await this.repository.initialize();
    const subscribers = await this.repository.listAutoCouponSubscribers(limit, afterSubjectHash);
    const results = {ready: 0, retry: 0, skipped: 0, other: 0};
    for (const subscriber of subscribers) {
      const result = await this.runOne(subscriber);
      if (Object.hasOwn(results, result.status)) results[result.status]++;
      else results.other++;
    }
    return {status: 'checked', checked: subscribers.length, results,
      nextCursor: subscribers.length ? subscribers.at(-1).subjectHash : null};
  }
}

module.exports = {AutoCouponGenerationCoordinator, publicCoupon};
