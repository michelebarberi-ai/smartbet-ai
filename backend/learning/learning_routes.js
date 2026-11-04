'use strict';

const {validToken} = require('./learning_core');
const {LearningRepository} = require('./learning_repository');
const {LearningService} = require('./learning_service');

function registerLearningRoutes(app, {requestApiFootball, env = process.env, now = () => new Date()}) {
  const requested = env.LEARNING_SERVER_ENABLED === 'true';
  const configured = requested && !!env.DATABASE_URL &&
    typeof env.LEARNING_ADMIN_TOKEN === 'string' && env.LEARNING_ADMIN_TOKEN.length >= 32 &&
    typeof env.LEARNING_SUBJECT_SALT === 'string' && env.LEARNING_SUBJECT_SALT.length >= 32;

  app.get('/learning/v1/status', (_req, res) => {
    return res.json({service: 'SmartBet Central Learning', version: 1,
      enabled: configured, mode: 'admin_staging', liveCalibration: false,
      requiresDatabase: true});
  });

  function authorize(req, res, next) {
    if (!configured) return res.status(503).json({success: false, error: 'Learning centralizzato non abilitato.'});
    if (!validToken(req.get('x-smartbet-learning-admin'), env.LEARNING_ADMIN_TOKEN)) {
      return res.status(401).json({success: false, error: 'Non autorizzato.'});
    }
    return next();
  }

  let service;
  function getService() {
    if (service) return service;
    // Lazy: other existing routes work even when PostgreSQL is unavailable.
    const {Pool} = require('pg');
    const pool = new Pool({
      connectionString: env.DATABASE_URL,
      max: 4,
      connectionTimeoutMillis: 5000,
      idleTimeoutMillis: 30000,
      ssl: env.LEARNING_PG_SSL === 'true' ? {rejectUnauthorized: true} : undefined,
    });
    const repository = new LearningRepository(pool);
    service = new LearningService({
      repository, subjectSalt: env.LEARNING_SUBJECT_SALT, now,
      fetchFixture: async fixtureId => {
        const result = await requestApiFootball({
          path: '/fixtures', query: {id: fixtureId}, ttlMs: 5 * 60 * 1000,
        });
        return result.data;
      },
    });
    return service;
  }

  async function handle(promise, res) {
    try { return await promise(); }
    catch (error) {
      console.error('CENTRAL LEARNING ERROR:', error?.code || error?.name || 'error');
      return res.status(503).json({success: false, error: 'Servizio learning temporaneamente non disponibile.'});
    }
  }

  // Staging endpoints are ADMIN ONLY. Never embed LEARNING_ADMIN_TOKEN in Flutter.
  app.post('/learning/v1/predictions', authorize, (req, res) => handle(async () => {
    const result = await getService().ingest(req.body);
    return res.status(result.status).json(result.body);
  }, res));

  // To be called by an authenticated external scheduled job, not by the app.
  app.post('/learning/v1/resolve', authorize, (req, res) => handle(async () => {
    return res.json(await getService().resolve());
  }, res));

  app.get('/learning/v1/summary', authorize, (req, res) => handle(async () => {
    return res.json(await getService().summary());
  }, res));
}

module.exports = {registerLearningRoutes};
