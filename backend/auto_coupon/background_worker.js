'use strict';

// P20.3C: dedicated Render BACKGROUND WORKER entry point (no HTTP listener).
// Not imported by the learning web server or Flutter app. Strict opt-in.
const {AutoCouponGenerationCoordinator} = require('./generation_coordinator');
const {createOfficialEngineAdapter, officialEngineConfiguration} =
  require('./official_engine_client');
const {createBackgroundScheduler} = require('./background_scheduler');

function backgroundWorkerConfiguration(env = process.env) {
  if (env.AUTO_COUPON_BACKGROUND_ENABLED !== 'true' ||
      env.AUTO_COUPON_WORKER_ENABLED !== 'true' ||
      env.AUTO_COUPON_PREFERENCES_ENABLED !== 'true' ||
      typeof env.DATABASE_URL !== 'string' || !env.DATABASE_URL.trim() ||
      !officialEngineConfiguration(env)) return null;

  // Avoid unbounded config values or accidental zero-delay busy loops.
  const intervalSeconds = env.AUTO_COUPON_BACKGROUND_INTERVAL_SECONDS === undefined
    ? 120 : Number(env.AUTO_COUPON_BACKGROUND_INTERVAL_SECONDS);
  const pageSize = env.AUTO_COUPON_BACKGROUND_PAGE_SIZE === undefined
    ? 20 : Number(env.AUTO_COUPON_BACKGROUND_PAGE_SIZE);
  if (!Number.isInteger(intervalSeconds) || intervalSeconds < 30 ||
      intervalSeconds > 1800 || !Number.isInteger(pageSize) ||
      pageSize < 1 || pageSize > 25) return null;
  return {intervalMs: intervalSeconds * 1000, pageSize};
}

async function main({env = process.env, poolFactory, schedulerFactory = createBackgroundScheduler,
  engineFactory = createOfficialEngineAdapter, repositoryFactory,
  processRef = process} = {}) {
  const config = backgroundWorkerConfiguration(env);
  if (!config) throw new Error('Background worker disabled or misconfigured');
  // Only this standalone process opens the Neon pool. Never put DATABASE_URL
  // or official engine tokens in logs or an app bundle.
  const createPool = poolFactory || (options => new (require('pg').Pool)(options));
  const pool = createPool({connectionString: env.DATABASE_URL, max: 3,
    connectionTimeoutMillis: 8000, idleTimeoutMillis: 15000,
    ssl: env.LEARNING_PG_SSL === 'true' ? {rejectUnauthorized: true} : undefined});
  try {
    const repository = repositoryFactory ? repositoryFactory(pool) :
      new (require('../learning/learning_repository').LearningRepository)(pool);
    const generator = engineFactory({env});
    if (typeof generator !== 'function') throw new Error('Official generator unavailable');
    await repository.initialize();
    const coordinator = new AutoCouponGenerationCoordinator({repository,
      generateOfficialCoupon: generator});
    const scheduler = schedulerFactory({runBatch: options => coordinator.runBatch(options),
      intervalMs: config.intervalMs, pageSize: config.pageSize,
      // Strictly generic operational status, no user identifiers or payloads.
      onError: () => console.error('AUTO COUPON BACKGROUND: cycle_failed')});

    const shutdown = () => {
      // A forced container shutdown may interrupt this wait; the Neon lease
      // expires and another worker safely reclaims the request.
      void scheduler.stop().then(() => pool.end()).catch(() => {
        console.error('AUTO COUPON BACKGROUND: shutdown_failed');
      });
    };
    processRef.once('SIGTERM', shutdown);
    processRef.once('SIGINT', shutdown);
    try {
      await scheduler.start();
    } catch (_) {
      console.error('AUTO COUPON BACKGROUND: initial_cycle_failed');
    }
    return scheduler;
  } catch (error) {
    await pool.end().catch(() => {});
    throw error;
  }
}

if (require.main === module) {
  require('dotenv').config();
  void main().catch(() => {
    console.error('AUTO COUPON BACKGROUND: startup_failed');
    process.exitCode = 1;
  });
}

module.exports = {backgroundWorkerConfiguration, main};
