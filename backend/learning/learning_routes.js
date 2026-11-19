'use strict';

const {validToken,hashClientId} = require('./learning_core');
const {encryptDeviceToken} = require('../auto_coupon/device_registration');
const {DailyPalinsestoSubscriptionRepository} = require('../daily_palinsesto/subscription_repository');
const {dispatchDailyPalinsesto} = require('../daily_palinsesto/dispatch');
const {digestPushReady} = require('../daily_palinsesto/apns_sender');
const {fetchDailyFixtures} = require('../daily_palinsesto/provider');
const {LearningRepository} = require('./learning_repository');
const {LearningService} = require('./learning_service');
const {registerAutoCouponWorkerRoute} = require('../auto_coupon/worker_route');
const {registrationReady} = require('../auto_coupon/device_registration');
const {apnsReady} = require('../auto_coupon/apns_provider');
const {registerAutoCouponPushDispatchRoute} = require('../auto_coupon/push_dispatch');
const {registerOnDemandCouponRoutes} = require('../auto_coupon/on_demand_coupon_routes');

function registerLearningRoutes(app, {requestApiFootball, env = process.env, now = () => new Date(), learningService = null, generateOfficialCoupon = null, onDemandWorkerRunning = false,
  verifyExternalWorker = null, wakeExternalWorker = null,
  requestDailyFixtures = null}) {
  const requested = env.LEARNING_SERVER_ENABLED === 'true';
  const configured = requested && !!env.DATABASE_URL &&
    typeof env.LEARNING_ADMIN_TOKEN === 'string' && env.LEARNING_ADMIN_TOKEN.length >= 32 &&
    typeof env.LEARNING_SUBJECT_SALT === 'string' && env.LEARNING_SUBJECT_SALT.length >= 32;

  const mobileEnabled = configured && env.LEARNING_MOBILE_INGEST_ENABLED === 'true';
  const historicalEnabled = mobileEnabled && env.LEARNING_RETRO_INGEST_ENABLED === 'true';
  const autoCouponPrefsEnabled = mobileEnabled && env.AUTO_COUPON_PREFERENCES_ENABLED === 'true';
  const pushRegistrationEnabled = autoCouponPrefsEnabled && registrationReady(env);
  // Completely separate from scheduled automatic betting coupons.
  // A schema-ready flag is only set after a separately authorized migration.
  const dailyPalinsestoRegistrationEnabled = mobileEnabled &&
    env.DAILY_PALINSESTO_SCHEMA_READY === 'true' &&
    env.DAILY_PALINSESTO_REGISTRATION_ENABLED === 'true' &&
    /^[0-9a-fA-F]{64}$/.test(env.DAILY_PALINSESTO_PUSH_TOKEN_ENCRYPTION_KEY || '') &&
    ['production','sandbox'].includes(env.APNS_ENVIRONMENT);
  const dailyPalinsestoDispatchReady = dailyPalinsestoRegistrationEnabled &&
    digestPushReady(env) &&
    typeof env.DAILY_PALINSESTO_WORKER_TOKEN === 'string' &&
    env.DAILY_PALINSESTO_WORKER_TOKEN.length >= 32;
  // Worker requires both an explicit flag and a verified official engine adapter.
  const workerReady = autoCouponPrefsEnabled &&
    env.AUTO_COUPON_WORKER_ENABLED === 'true' &&
    typeof env.AUTO_COUPON_WORKER_TOKEN === 'string' &&
    env.AUTO_COUPON_WORKER_TOKEN.length >= 32 &&
    typeof generateOfficialCoupon === 'function';

  // All independent gates and the genuine official generator are required.
  const pushDispatchReady = workerReady && pushRegistrationEnabled && apnsReady({env});

  app.get('/learning/v1/status', (_req, res) => {
    return res.json({service: 'SmartBet Central Learning', version: 1,
      enabled: configured, mobileIngestEnabled: mobileEnabled,
      retrospectiveIngestEnabled: historicalEnabled,
      autoCouponPreferencesEnabled: autoCouponPrefsEnabled,
      autoCouponGenerationEnabled: false, autoCouponPushEnabled: false,
      autoCouponWorkerReady: workerReady,
      autoCouponDeviceRegistrationEnabled: pushRegistrationEnabled,
      autoCouponPushDispatchReady: pushDispatchReady,
      dailyPalinsestoRegistrationEnabled,
      dailyPalinsestoPushEnabled: dailyPalinsestoDispatchReady,
      onDemandCouponRequestsEnabled: onDemandWorkerRunning === true && mobileEnabled &&
        env.ON_DEMAND_COUPON_REQUESTS_ENABLED==='true' &&
        typeof generateOfficialCoupon==='function',
      onDemandCouponWorkerEnabled: mobileEnabled &&
        env.ON_DEMAND_COUPON_REQUESTS_ENABLED==='true' &&
        env.ON_DEMAND_COUPON_WORKER_ENABLED==='true' &&
        typeof env.ON_DEMAND_COUPON_WORKER_TOKEN==='string' &&
        env.ON_DEMAND_COUPON_WORKER_TOKEN.length>=32 &&
        typeof generateOfficialCoupon==='function',
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

  // Retroactive imports are separately gated, stored in a different table,
  // and never included in live calibration or official market summaries.
  app.post('/learning/v1/mobile/retrospective', authorizeMobile, (req, res) => handle(async () => {
    if (!historicalEnabled) return res.status(503).json({success: false, error: 'Archivio storico non abilitato.'});
    if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body) ||
        Object.prototype.hasOwnProperty.call(req.body, 'clientId') ||
        Object.prototype.hasOwnProperty.call(req.body, 'predictions')) {
      return res.status(400).json({success: false, error: 'Payload non valido.'});
    }
    const result = await getService().ingestRetrospective({
      clientId: req.learningClientId, snapshots: req.body.snapshots,
    });
    res.set('Cache-Control', 'no-store');
    return res.status(result.status).json(result.body);
  }, res));

  // Authenticated draft synchronization. No worker, no push, no active schedule.
  app.post('/learning/v1/mobile/auto-coupon/preferences', authorizeMobile, (req, res) => handle(async () => {
    if (!autoCouponPrefsEnabled) return res.status(503).json({success: false,
      error: 'Sincronizzazione AutoSchedina non abilitata.'});
    if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body) ||
        Object.keys(req.body).length !== 1 || !Object.hasOwn(req.body, 'preferences')) {
      return res.status(400).json({success: false, error: 'Payload non valido.'});
    }
    const result = await getService().saveAutoCouponPreferences({
      clientId: req.learningClientId, preferences: req.body.preferences,
    });
    res.set('Cache-Control', 'no-store');
    return res.status(result.status).json(result.body);
  }, res));

  app.get('/learning/v1/mobile/auto-coupon/preferences', authorizeMobile, (req, res) => handle(async () => {
    if (!autoCouponPrefsEnabled) return res.status(503).json({success: false,
      error: 'Sincronizzazione AutoSchedina non abilitata.'});
    const result = await getService().readAutoCouponPreferences(req.learningClientId);
    res.set('Cache-Control', 'no-store');
    return res.status(result.status).json(result.body);
  }, res));

  app.get('/learning/v1/mobile/auto-coupon/today', authorizeMobile, (req, res) => handle(async () => {
    if (!autoCouponPrefsEnabled) return res.status(503).json({success: false,
      error: 'AutoSchedina non abilitata sul server.'});
    const result = await getService().readTodayAutoCoupon(req.learningClientId);
    res.set('Cache-Control', 'no-store');
    return res.status(result.status).json(result.body);
  }, res));

  // Explicit iPhone opt-in. APNs tokens are encrypted before database insertion.
  // Registration does NOT enable scheduled work or transmit push notifications.
  app.post('/learning/v1/mobile/auto-coupon/push/register', authorizeMobile,
    (req, res) => handle(async () => {
      if (!pushRegistrationEnabled) return res.status(503).json({success: false,
        error: 'Registrazione notifiche non abilitata.'});
      if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body) ||
          Object.keys(req.body).length !== 1 || !Object.hasOwn(req.body, 'deviceToken')) {
        return res.status(400).json({success: false, error: 'Payload non valido.'});
      }
      const result = await getService().registerAutoCouponPushDevice({
        clientId: req.learningClientId, deviceToken: req.body.deviceToken,
        environment: env.APNS_ENVIRONMENT,
        encryptionKey: env.AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY,
      });
      res.set('Cache-Control', 'no-store');
      return res.status(result.status).json(result.body);
    }, res));

  app.post('/learning/v1/mobile/auto-coupon/push/unregister', authorizeMobile,
    (req, res) => handle(async () => {
      if (!pushRegistrationEnabled) return res.status(503).json({success: false,
        error: 'Registrazione notifiche non abilitata.'});
      if (req.body && (typeof req.body !== 'object' ||
          Array.isArray(req.body) || Object.keys(req.body).length)) {
        return res.status(400).json({success: false, error: 'Payload non valido.'});
      }
      const result = await getService().unregisterAutoCouponPushDevice(req.learningClientId);
      res.set('Cache-Control', 'no-store');
      return res.status(result.status).json(result.body);
    }, res));

  // B73: explicit iPhone consent; this never subscribes a user from the
  // old automatic-coupon settings, and it never generates betting coupons.
  app.post('/learning/v1/mobile/palinsesto/subscribe', authorizeMobile,
    (req, res) => handle(async () => {
      if (!dailyPalinsestoRegistrationEnabled) return res.status(503).json({
        success:false,error:'Riepilogo programmato non ancora attivo.',
      });
      const body=req.body;
      if (!body || typeof body!=='object' || Array.isArray(body) ||
          Object.keys(body).sort().join(',')!=='deviceToken,hour,minute' ||
          typeof body.deviceToken!=='string' ||
          !/^[0-9a-fA-F]{64}$/.test(body.deviceToken) ||
          !Number.isInteger(body.hour) || body.hour<0 || body.hour>23 ||
          !Number.isInteger(body.minute) || body.minute<0 || body.minute>59) {
        return res.status(400).json({success:false,error:'Parametri non validi.'});
      }
      const main=getService().repository;
      await main.initialize();
      const subjectHash=hashClientId(req.learningClientId,env.LEARNING_SUBJECT_SALT);
      const encrypted=encryptDeviceToken({
        deviceToken:body.deviceToken,subjectHash,
        environment:env.APNS_ENVIRONMENT,
        keyHex:env.DAILY_PALINSESTO_PUSH_TOKEN_ENCRYPTION_KEY,
      });
      const repository=new DailyPalinsestoSubscriptionRepository(main.pool);
      await repository.upsert({
        subjectHash,hour:body.hour,minute:body.minute,
        environment:env.APNS_ENVIRONMENT,...encrypted,
      });
      return res.json({success:true,registered:true,
        pushActive:dailyPalinsestoDispatchReady});
    }, res));

  app.post('/learning/v1/mobile/palinsesto/unsubscribe', authorizeMobile,
    (req, res) => handle(async () => {
      if (!mobileEnabled || env.DAILY_PALINSESTO_SCHEMA_READY!=='true') {
        return res.status(503).json({success:false,error:'Servizio non disponibile.'});
      }
      if (req.body && (typeof req.body!=='object' ||
          Array.isArray(req.body) || Object.keys(req.body).length)) {
        return res.status(400).json({success:false,error:'Parametri non validi.'});
      }
      const main=getService().repository;
      await main.initialize();
      const repository=new DailyPalinsestoSubscriptionRepository(main.pool);
      await repository.unsubscribe(
        hashClientId(req.learningClientId,env.LEARNING_SUBJECT_SALT));
      return res.json({success:true,registered:false,pushActive:false});
    },res));

  // Dedicated morning worker, callable only by trusted scheduling code.
  // One fixture calendar read across the batch; no timer started here.
  app.post('/learning/v1/palinsesto/worker/dispatch', (req,res) =>
    handle(async()=>{
      if (!dailyPalinsestoDispatchReady) return res.status(503).json({
        success:false,error:'Invio palinsesto non abilitato.',
      });
      if (!validToken(req.get('x-goalvdline-palinsesto-worker-token'),
        env.DAILY_PALINSESTO_WORKER_TOKEN)) {
        return res.status(401).json({success:false,error:'Non autorizzato.'});
      }
      const body=req.body || {};
      if (typeof body!=='object' || Array.isArray(body) ||
          Object.keys(body).some(x=>!['limit','afterSubjectHash'].includes(x)) ||
          (body.limit!==undefined && (!Number.isInteger(body.limit) ||
           body.limit<1 || body.limit>25)) ||
          (body.afterSubjectHash!==undefined && body.afterSubjectHash!==null &&
           (typeof body.afterSubjectHash!=='string' ||
            !/^[0-9a-f]{64}$/.test(body.afterSubjectHash)))) {
        return res.status(400).json({success:false,error:'Parametri non validi.'});
      }
      const main=getService().repository;
      await main.initialize();
      const repository=new DailyPalinsestoSubscriptionRepository(main.pool);
      const result=await dispatchDailyPalinsesto({
        repository,env,now,
        fetchDailyFixtures:requestDailyFixtures ||
          (dayKey=>fetchDailyFixtures(dayKey,{env})),
        limit:body.limit??20,afterSubjectHash:body.afterSubjectHash??null,
      });
      return res.json({success:true,...result});
    },res));

  // Protected server-to-server route. No scheduling, no push and no invented
  // predictions. If an official generator is absent it fails closed.
  registerAutoCouponWorkerRoute(app, {
    enabled: workerReady,
    workerToken: env.AUTO_COUPON_WORKER_TOKEN,
    getRepository: () => getService().repository,
    generateOfficialCoupon, now,
  });

  // B47: on-demand jobs are opt-in and separate from the daily scheduler.
  // The mobile POST queues only; a trusted worker must finish official output.
  registerOnDemandCouponRoutes(app, {
    env,mobileEnabled,authorizeMobile,workerRunning:onDemandWorkerRunning,
    getLearningService:getService,
    generateOfficialCoupon,now,verifyExternalWorker,wakeExternalWorker,
  });

  // Invoked explicitly by the trusted job *after* official generation.
  // No timer and no APNs calls until all server flags/keys are configured.
  registerAutoCouponPushDispatchRoute(app, {
    enabled: pushDispatchReady,
    workerToken: env.AUTO_COUPON_WORKER_TOKEN, env, now,
    getRepository: () => getService().repository,
  });

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
