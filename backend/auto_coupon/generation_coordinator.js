'use strict';

// B45 P8: server-side orchestration, never a replacement for the official
// Flutter coupon ranking engine. This module does nothing until an external
// worker explicitly calls it with a verified, equivalent official generator.
const {dailyRunStatus, validateGeneratedCoupon} = require('./daily_schedule');

const SUBJECT_HASH = /^[0-9a-f]{64}$/;
const MAX_BATCH = 100;
const LEASE_RENEWAL_MS = 60_000;
const LEASE_TOKEN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
  // Retain only the bounded official day window needed by push validation.
  const dateWindow = coupon.windowDays === 2 || coupon.windowDays === 3
    ? {windowDays:coupon.windowDays} : {};
  if (!coupon.coupons) return {...dateWindow, events};
  return {...dateWindow, events, coupons:coupon.coupons.map(({name,events}) => ({
    name, events:publicEvents(events),
  }))};
}

class AutoCouponGenerationCoordinator {
  constructor({repository, generateOfficialCoupon = null, now = () => new Date(),
    leaseRenewalMs = LEASE_RENEWAL_MS}) {
    this.repository = repository;
    this.generateOfficialCoupon = generateOfficialCoupon;
    this.now = now;
    this.leaseRenewalMs = leaseRenewalMs;
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
    if (!Number.isInteger(claim.attempts) || claim.attempts < 1 || claim.attempts > 5 ||
        typeof claim.leaseToken !== 'string' || !LEASE_TOKEN.test(claim.leaseToken) ||
        typeof this.repository.renewAutoCouponLease !== 'function') {
      // An old or incompatible repository may not publish un-fenced results.
      return {status: 'invalid_lease'};
    }

    const lease = {subjectHash, dayKey: due.dayKey,
      attempts: claim.attempts, leaseToken: claim.leaseToken};
    let leaseLost = false;
    let renewalPending = Promise.resolve();
    const renew = async () => {
      try {
        return (await this.repository.renewAutoCouponLease(lease)) === true;
      } catch (_) {
        return false;
      }
    };
    // Node timers are not durable work queues. Their only purpose is to
    // maintain the Neon lease while the remote official engine is working.
    const timer = setInterval(() => {
      renewalPending = renewalPending.then(async () => {
        if (!leaseLost && !(await renew())) leaseLost = true;
      });
    }, this.leaseRenewalMs);
    timer.unref?.();

    let proposed;
    let providerFailed = false;
    try {
      proposed = await this.generateOfficialCoupon({
        subjectHash, dayKey: due.dayKey, preferences, now,
      });
    } catch (_) {
      providerFailed = true;
    } finally {
      clearInterval(timer);
      await renewalPending;
    }
    // Fence every completion, including errors. A stale owner must not write
    // READY or RETRY after another worker has reclaimed its lease.
    if (leaseLost || !(await renew())) return {status: 'superseded'};
    const checkedAt = this.now();
    if (providerFailed) {
      const completed = await this.repository.finishAutoCouponRun({
        ...lease, outcome: 'retry', reason: 'provider_unavailable',
        now: checkedAt, retryMinutes: 15,
      });
      return completed ? {status: 'retry', reason: 'provider_unavailable'} :
        {status: 'superseded'};
    }

    // An official, legitimately empty generation is a sporting-data outcome,
    // not a provider/transport fault and never a reason to invent selections.
    if (proposed && !Array.isArray(proposed) &&
        proposed.status === 'no_coupon') {
      const reason = Object.keys(proposed).length === 1 ?
        'no_coupon' : 'insufficient_events';
      const completed = await this.repository.finishAutoCouponRun({
        ...lease, outcome: 'retry', reason,
        now: checkedAt, retryMinutes: 60,
      });
      return completed ? {status: 'retry', reason} :
        {status: 'superseded'};
    }

    const validation = validateGeneratedCoupon({coupon: proposed,
      preferences, now: checkedAt});
    if (!validation.valid || validation.dayKey !== due.dayKey) {
      const completed = await this.repository.finishAutoCouponRun({
        ...lease, outcome: 'retry', reason: 'insufficient_events',
        now: checkedAt, retryMinutes: 60,
      });
      return completed ? {status: 'retry', reason: 'insufficient_events'} :
        {status: 'superseded'};
    }
    const coupon = publicCoupon(proposed);
    const completed = await this.repository.finishAutoCouponRun({
      ...lease, outcome: 'ready', coupon, now: checkedAt,
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
    if (typeof this.repository.finalizeExpiredAutoCouponRuns === 'function') {
      await this.repository.finalizeExpiredAutoCouponRuns();
    }
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
