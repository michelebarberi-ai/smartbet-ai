'use strict';

const {validToken} = require('./learning_core');
const {LearningRepository} = require('./learning_repository');
const {LearningService} = require('./learning_service');

function registerLearningRoutes(app, {requestApiFootball, env = process.env, now = () => new Date(), learningService = null}) {
  const requested = env.LEARNING_SERVER_ENABLED === 'true';
  const configured = requested && !!env.DATABASE_URL &&
    typeof env.LEARNING_ADMIN_TOKEN === 'string' && env.LEARNING_ADMIN_TOKEN.length >= 32 &&
    typeof env.LEARNING_SUBJECT_SALT === 'string' && env.LEARNING_SUBJECT_SALT.length >= 32;

  const mobileEnabled = configured && env.LEARNING_MOBILE_INGEST_ENABLED === 'true';

  app.get('/learning/v1/status', (_req, res) => {
    return res.json({service: 'SmartBet Central Learning', version: 1,
      enabled: configured, mobileIngestEnabled: mobileEnabled,
      mode: 'admin_staging', liveCalibration: false,
      requiresDatabase: true});
  });

  function authorize(req, res, next) {
    if (!configured) return res.status(503).json({success: false, error: 'Learning centralizzato non abilitato.'});
    if (!validToken(req.get('x-smartbet-learning-admin'), env.LEARNING_ADMIN_TOKEN)) {
      return res.status(401).json({success: false, error: 'Non autorizzato.'});
    }
    return next();
  }

  // No public sign-up: only the admin can issue or revoke scoped device
  // credentials. Feature flag is independent from P23A admin staging.
  function authorizeMobile(req, res, next) {
    if (!mobileEnabled) return res.status(503).json({success: false,
      error: 'Invio mobile non abilitato.'});
    const header = req.get('authorization') || '';
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(header);
    if (!match) return res.status(401).json({success: false, error: 'Non autorizzato.'});
    return handle(async () => {
      const clientId = await getService().authenticateMobileToken(match[1]);
      if (!clientId) return res.status(401).json({success: false, error: 'Non autorizzato.'});
      req.learningClientId = clientId;
      return next();
    }, res);
  }

  let service = learningService;
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

  app.post('/learning/v1/clients/provision', authorize, (req, res) => handle(async () => {
    if (!mobileEnabled) return res.status(503).json({success: false,
      error: 'Invio mobile non abilitato.'});
    res.set('Cache-Control', 'no-store');
    return res.status(201).json(await getService().provisionMobileClient());
  }, res));

  app.post('/learning/v1/clients/revoke', authorize, (req, res) => handle(async () => {
    const result = await getService().revokeMobileClient(req.body?.clientId);
    return res.status(result.status).json(result.body);
  }, res));

  // The authenticated client identity comes from the SERVER, never the body.
  // Only original predictions before server-verified kickoff can be ingested.
  // Historical snapshots are intentionally not supported on this endpoint.
  app.post('/learning/v1/mobile/predictions', authorizeMobile, (req, res) => handle(async () => {
    if (!req.body || Object.prototype.hasOwnProperty.call(req.body, 'clientId') ||
        Object.prototype.hasOwnProperty.call(req.body, 'historical')) {
      return res.status(400).json({success: false, error: 'Payload non valido.'});
    }
    const result = await getService().ingest({
      clientId: req.learningClientId, predictions: req.body.predictions,
    });
    res.set('Cache-Control', 'no-store');
    return res.status(result.status).json(result.body);
  }, res));

  app.post('/learning/v1/mobile/erase', authorizeMobile, (req, res) => handle(async () => {
    res.set('Cache-Control', 'no-store');
    return res.json(await getService().eraseMobileClient(req.learningClientId));
  }, res));

  app.post('/learning/v1/clients/erase', authorize, (req, res) => handle(async () => {
    const clientId = req.body?.clientId;
    if (typeof clientId !== 'string' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(clientId)) {
      return res.status(400).json({success: false, error: 'Client non valido.'});
    }
    return res.json(await getService().eraseMobileClient(clientId));
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
