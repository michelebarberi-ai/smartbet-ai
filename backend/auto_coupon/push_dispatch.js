'use strict';

// B45 P13: durable, permissioned notification dispatch. This is NOT a timer
// or a coupon engine. A trusted external scheduler must invoke it only AFTER
// the official coupon worker has saved a validated daily coupon.
const {validToken} = require('../learning/learning_core');
const {localClock, allowedRomeDays} = require('./daily_schedule');
const {decryptDeviceToken} = require('./device_registration');
const {sendAutoCouponReadyPush} = require('./apns_provider');

const ROUTE = '/learning/v1/auto-coupon/worker/push';
const SUBJECT_HASH = /^[0-9a-f]{64}$/;
const MAX_BATCH = 25;

function normalizePushBatch(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => key !== 'limit' && key !== 'afterSubjectHash')) return null;
  const limit = value.limit ?? 20;
  const afterSubjectHash = value.afterSubjectHash ?? null;
  if (!Number.isInteger(limit) || limit < 1 || limit > MAX_BATCH ||
      (afterSubjectHash !== null && !SUBJECT_HASH.test(afterSubjectHash))) return null;
  return {limit, afterSubjectHash};
}

function futureCoupon(coupon, dayKey, now) {
  const windowDays = coupon?.windowDays ?? 1;
  if (![1, 2, 3].includes(windowDays) ||
      localClock(now).dayKey !== dayKey ||
      !coupon || !Array.isArray(coupon.events) ||
      coupon.events.length < 3 || coupon.events.length > 15) return false;
  if (coupon.coupons !== undefined) {
    if (!Array.isArray(coupon.coupons) || coupon.coupons.length !== 3) return false;
    const signatures = new Set();
    for (let i=0;i<3;i++) {
      const variant = coupon.coupons[i];
      if (!variant || !Array.isArray(variant.events) ||
          variant.events.length !== coupon.events.length) return false;
      const signature = [];
      for (let j=0;j<variant.events.length;j++) {
        const e = variant.events[j], base = coupon.events[j];
        if (!e || e.fixtureId !== base.fixtureId || e.kickoffAt !== base.kickoffAt ||
            typeof e.market !== 'string' || !e.market.trim() ||
            !Number.isFinite(e.marketProbability) || e.marketProbability < 0 ||
            e.marketProbability > 100 || !Number.isFinite(e.odds) || e.odds <= 1) return false;
        signature.push(`${e.fixtureId}/${e.market}`);
      }
      if (i===0 && JSON.stringify(variant.events)!==JSON.stringify(coupon.events)) return false;
      signatures.add(signature.join('|'));
    }
    if (signatures.size!==3) return false;
  }
  const ids = new Set();
  const allowedDays = allowedRomeDays(now, windowDays);
  return coupon.events.every(event => {
    if (!Number.isSafeInteger(event?.fixtureId) || event.fixtureId <= 0 ||
        ids.has(event.fixtureId) || typeof event.market !== 'string' ||
        !event.market.trim() || !Number.isFinite(event.marketProbability) ||
        event.marketProbability < 0 || event.marketProbability > 100 ||
        typeof event.kickoffAt !== 'string') return false;
    ids.add(event.fixtureId);
    const kickoff = new Date(event.kickoffAt);
    return Number.isFinite(kickoff.getTime()) && kickoff > now &&
      allowedDays.has(localClock(kickoff).dayKey);
  });
}

class AutoCouponPushDispatcher {
  constructor({repository, env = process.env, now = () => new Date(),
    send = sendAutoCouponReadyPush}) {
    this.repository = repository;
    this.env = env;
    this.now = now;
    this.send = send;
  }

  async runOne({subjectHash, dayKey, now}) {
    const claim = await this.repository.claimAutoCouponPush({subjectHash, dayKey, now});
    if (!claim) return 'skipped';
    let outcome = 'retry';
    let reason = 'transport_error';
    try {
      const [saved, device] = await Promise.all([
        this.repository.readAutoCouponDay({subjectHash, dayKey}),
        this.repository.readAutoCouponPushDevice(subjectHash),
      ]);
      if (saved?.status !== 'ready' || !futureCoupon(saved.coupon, dayKey, now)) {
        outcome = 'unavailable'; reason = 'stale_or_invalid_coupon';
      } else if (!device) {
        outcome = 'unavailable'; reason = 'registration_missing';
      } else if (device.environment !== this.env.APNS_ENVIRONMENT) {
        reason = 'environment_mismatch';
      } else {
        const token = decryptDeviceToken({record: device, subjectHash,
          keyHex: this.env.AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY});
        const response = await this.send({env: this.env, deviceToken: token,
          dayKey, coupon: saved.coupon, now: () => now});
        if (response?.status === 'accepted_by_apns') {
          outcome = 'sent'; reason = null;
        } else if (response?.status === 'unregistered_device' ||
                   response?.status === 'invalid_device_token') {
          outcome = 'unregistered'; reason = 'device_unregistered';
          // Do not delete a concurrently replaced registration.
          await this.repository.deleteAutoCouponPushDeviceIfMatch({
            subjectHash, ciphertext: device.ciphertext,
          });
        } else if (response?.status === 'rejected_by_apns') {
          reason = 'apns_rejected';
        }
      }
    } catch (_) {
      // Never log APNs tokens, signing keys or decrypted device identities.
      reason = 'transport_error';
    }
    const finished = await this.repository.finishAutoCouponPush({
      subjectHash, dayKey, attempts: claim.attempts, outcome, reason, now,
    });
    return finished ? (outcome === 'retry' && claim.attempts >= 5 ?
      'unavailable' : outcome) : 'superseded';
  }

  async runBatch({limit = 20, afterSubjectHash = null} = {}) {
    if (!normalizePushBatch({limit, afterSubjectHash})) {
      throw new RangeError('Invalid push batch request');
    }
    const now = this.now();
    if (!(now instanceof Date) || !Number.isFinite(now.getTime())) {
      throw new TypeError('Invalid server clock');
    }
    const dayKey = localClock(now).dayKey;
    await this.repository.initialize();
    const candidates = await this.repository.listPendingAutoCouponPushes({
      dayKey, now, limit, afterSubjectHash,
    });
    const results = {sent: 0, retry: 0, unavailable: 0, unregistered: 0,
      skipped: 0, superseded: 0};
    for (const candidate of candidates) {
      const status = await this.runOne({subjectHash: candidate.subjectHash, dayKey, now});
      if (Object.hasOwn(results, status)) results[status]++;
    }
    return {status: 'checked', checked: candidates.length, results,
      nextCursor: candidates.length ? candidates.at(-1).subjectHash : null};
  }
}

function registerAutoCouponPushDispatchRoute(app, {enabled = false, workerToken,
  getRepository, env = process.env, now = () => new Date(),
  send = sendAutoCouponReadyPush} = {}) {
  app.post(ROUTE, async (req, res) => {
    res.set('Cache-Control', 'no-store');
    if (!enabled || typeof workerToken !== 'string' || workerToken.length < 32) {
      return res.status(503).json({success: false, error: 'Notifiche non abilitate.'});
    }
    if (!validToken(req.get('x-goalvdline-worker-token'), workerToken)) {
      return res.status(401).json({success: false, error: 'Non autorizzato.'});
    }
    const batch = normalizePushBatch(req.body);
    if (!batch) return res.status(400).json({success: false, error: 'Parametri non validi.'});
    try {
      const dispatcher = new AutoCouponPushDispatcher({repository: getRepository(),
        env, now, send});
      return res.status(200).json({success: true, ...await dispatcher.runBatch(batch)});
    } catch (error) {
      console.error('AUTO COUPON PUSH WORKER ERROR:', error?.code || error?.name || 'error');
      return res.status(503).json({success: false, error: 'Invio notifiche non disponibile.'});
    }
  });
}

module.exports = {
  ROUTE, normalizePushBatch, futureCoupon, AutoCouponPushDispatcher,
  registerAutoCouponPushDispatchRoute,
};
