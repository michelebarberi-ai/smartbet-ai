'use strict';

// B45 P10: a guarded entry point for a future external periodic worker.
// Never launched by the phone or this server, and never generates a coupon
// unless an explicit official-engine adapter is installed by the backend.
const {validToken} = require('../learning/learning_core');
const {AutoCouponGenerationCoordinator} = require('./generation_coordinator');

const ROUTE = '/learning/v1/auto-coupon/worker/run';
const LIMIT = 25;
const CURSOR = /^[0-9a-f]{64}$/;

function normalizeBatchRequest(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  if (Object.keys(value).some(key => key !== 'limit' && key !== 'afterSubjectHash')) return null;
  const limit = value.limit ?? 20;
  const afterSubjectHash = value.afterSubjectHash ?? null;
  if (!Number.isInteger(limit) || limit < 1 || limit > LIMIT) return null;
  if (afterSubjectHash !== null &&
      (typeof afterSubjectHash !== 'string' || !CURSOR.test(afterSubjectHash))) return null;
  return {limit, afterSubjectHash};
}

function registerAutoCouponWorkerRoute(app, {enabled = false, workerToken = null,
  getRepository, generateOfficialCoupon = null, now = () => new Date()} = {}) {
  // Route is always present so that disabled instances fail explicitly.
  app.post(ROUTE, async (req, res) => {
    res.set('Cache-Control', 'no-store');
    if (!enabled || typeof generateOfficialCoupon !== 'function' ||
        typeof workerToken !== 'string' || workerToken.length < 32) {
      return res.status(503).json({success: false, error: 'Worker non abilitato.'});
    }
    if (!validToken(req.get('x-goalvdline-worker-token'), workerToken)) {
      return res.status(401).json({success: false, error: 'Non autorizzato.'});
    }
    const input = normalizeBatchRequest(req.body);
    if (!input) return res.status(400).json({success: false, error: 'Parametri non validi.'});
    try {
      const repository = getRepository();
      const worker = new AutoCouponGenerationCoordinator({
        repository, generateOfficialCoupon, now,
      });
      const result = await worker.runBatch(input);
      return res.status(200).json({success: true, ...result});
    } catch (error) {
      // Do not leak database errors, keys, per-user data or provider payloads.
      console.error('AUTO COUPON WORKER ERROR:', error?.code || error?.name || 'error');
      return res.status(503).json({success: false, error: 'Worker non disponibile.'});
    }
  });
}

module.exports = {registerAutoCouponWorkerRoute, normalizeBatchRequest, ROUTE};
