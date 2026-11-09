'use strict';

// Dedicated API for central learning. Does NOT create an OpenAI client,
// expose the paid /analyze route, or start background timers.
require('dotenv').config();
const express = require('express');
const {registerLearningRoutes} = require('./learning/learning_routes');
const {Pool} = require('pg');

// Read-only database connectivity and schema probe. It never enables ingest or
// touches prediction rows, and it deliberately omits connection error details.
async function probeLearningDatabase({env = process.env, poolFactory = options => new Pool(options)} = {}) {
  if (typeof env.DATABASE_URL !== 'string' || !env.DATABASE_URL.trim()) {
    return {databaseChecked: false, databaseReachable: false, schemaReady: false};
  }
  let pool;
  try {
    pool = poolFactory({
      connectionString: env.DATABASE_URL,
      max: 1,
      connectionTimeoutMillis: 4000,
      idleTimeoutMillis: 1000,
      query_timeout: 5000,
      ssl: env.LEARNING_PG_SSL === 'true' ? {rejectUnauthorized: true} : undefined,
    });
    const result = await pool.query(`
      SELECT
        to_regclass('public.sb_learning_predictions_v1') IS NOT NULL AS predictions_present,
        to_regclass('public.sb_learning_clients_v1') IS NOT NULL AS clients_present
    `);
    const row = result?.rows?.[0];
    return {
      databaseChecked: true,
      databaseReachable: true,
      schemaReady: row?.predictions_present === true && row?.clients_present === true,
    };
  } catch (_error) {
    return {databaseChecked: true, databaseReachable: false, schemaReady: false};
  } finally {
    if (pool) {
      try { await pool.end(); } catch (_error) { /* Never expose pool errors. */ }
    }
  }
}

const API_FOOTBALL_ORIGIN = 'https://v3.football.api-sports.io';

async function requestFixture({path, query}, {env = process.env, fetchImpl = fetch} = {}) {
  if (path !== '/fixtures') throw new Error('Unsupported football request');
  const id = Number(query?.id);
  if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Invalid fixture id');
  const apiKey = env.FOOTBALL_API_KEY;
  if (typeof apiKey !== 'string' || !apiKey.trim()) {
    throw new Error('Football provider not configured');
  }

  const url = new URL('/fixtures', API_FOOTBALL_ORIGIN);
  url.searchParams.set('id', String(id));
  const response = await fetchImpl(url, {
    method: 'GET',
    headers: {'x-apisports-key': apiKey, accept: 'application/json'},
    redirect: 'error',
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('Football provider unavailable');
  const data = await response.json();
  const errors = data?.errors;
  if ((Array.isArray(errors) && errors.length > 0) ||
      (errors && !Array.isArray(errors) && Object.keys(errors).length > 0) ||
      !Array.isArray(data?.response) || data.response.length !== 1 ||
      Number(data.response[0]?.fixture?.id) !== id) {
    throw new Error('Football provider response not verifiable');
  }
  return {data};
}

function createLearningOnlyApp({env = process.env, fetchImpl = fetch, poolFactory,
  generateOfficialCoupon = null} = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use((_req, res, next) => {res.set('Cache-Control', 'no-store'); next();});
  app.use(express.json({limit: '64kb'}));

  // Process health is not a guarantee of database reachability.
  app.get('/health', (_req, res) => res.json({
    service: 'GoalVdLine Central Learning', running: true, databaseChecked: false,
  }));

// Public response exposes only boolean readiness, never Neon credentials or
// database errors. Share a single probe per minute to limit free-tier usage.
let lastResult = null;
let lastCheckedAt = 0;
let pendingProbe = null;
app.get('/health/database', async (_req, res) => {
  const now = Date.now();
  if (!pendingProbe && (lastResult === null || now - lastCheckedAt >= 60000)) {
    pendingProbe = probeLearningDatabase({env, poolFactory})
      .then(result => {
        lastResult = result;
        lastCheckedAt = Date.now();
        return result;
      })
      .finally(() => { pendingProbe = null; });
  }
  const result = pendingProbe ? await pendingProbe : lastResult;
  return res.status(result.databaseReachable && result.schemaReady ? 200 : 503).json({
    service: 'GoalVdLine Central Learning', ...result,
    learningEnabled: false,
  });
});

  registerLearningRoutes(app, {
    env, generateOfficialCoupon,
    requestApiFootball: (request) => requestFixture(request, {env, fetchImpl}),
  });
  return app;
}

if (require.main === module) {
  const port = Number(process.env.PORT) || 3000;
  createLearningOnlyApp().listen(port, '0.0.0.0', () => {
    console.log(`GoalVdLine central learning listening on port ${port}`);
  });
}

module.exports = {createLearningOnlyApp, requestFixture, probeLearningDatabase};
