'use strict';

const {LearningRepository} = require('./learning/learning_repository');
const {mobileTokenHash} = require('./learning/learning_service');

const MOBILE_BEARER = /^Bearer ([A-Za-z0-9_-]{43})$/;
const MAX_IDENTITIES = 10000;

function boundedInteger(raw, fallback, minimum, maximum) {
  if (raw === undefined || raw === null || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    return fallback;
  }
  return value;
}

/**
 * Authenticates the existing server-provisioned LEARNING mobile token against
 * the same Neon table (hashed credentials; no admin token on the iPhone).
 * This DB connection is lazy. Production activation REQUIRES a separately
 * configured, narrowly scoped connection, and a client release first.
 */
function createLearningMobileAuthenticator({env = process.env, now = () => new Date(),
  poolFactory = null} = {}) {
  let repository = null;
  return async function authenticate(token) {
    if (!MOBILE_BEARER.test('Bearer ' + token)) return null;
    if (!env.PUBLIC_API_AUTH_DATABASE_URL) {
      throw new Error('Public API auth database is not configured');
    }
    if (!repository) {
      const createPool = poolFactory || ((options) => {
        const {Pool} = require('pg');
        return new Pool(options);
      });
      const pool = createPool({
        connectionString: env.PUBLIC_API_AUTH_DATABASE_URL,
        max: 3,
        connectionTimeoutMillis: 4000,
        idleTimeoutMillis: 30000,
        ssl: env.PUBLIC_API_AUTH_PG_SSL === 'true'
          ? {rejectUnauthorized: true} : undefined,
      });
      repository = new LearningRepository(pool);
    }
    return repository.findValidClient(mobileTokenHash(token), now());
  };
}

/**
 * Cheap, fail-safe per-instance caps for API calls. No caller-supplied
 * X-Forwarded-For: addresses must be assigned by the trusted HTTP stack.
 * Per-client identity becomes authoritative ONLY after database validation.
 * A process restart/another instance has its own budget; these are NOT
 * global billing guarantees. Keep an external provider spending cap too.
 *
 * tokenMode: 'off' (default and backwards compatible), or 'require'.
 * Never activate 'require' until clients can send provisioned credentials.
 */
function createPublicApiGuard({
  env = process.env,
  now = () => Date.now(),
  authenticate = null,
  tokenMode = 'off',
  group = 'ai',
} = {}) {
  if (!['off', 'require'].includes(tokenMode)) {
    throw new Error('Unsupported public API token mode');
  }
  const isAi = group === 'ai';
  const clientPeriod = isAi ? 60 * 60 * 1000 : 60 * 1000;
  const globalPeriod = 24 * 60 * 60 * 1000;
  const perClientLimit = boundedInteger(
    env[isAi ? 'PUBLIC_AI_CLIENT_HOURLY_LIMIT' : 'PUBLIC_FOOTBALL_CLIENT_MINUTE_LIMIT'],
    isAi ? 90 : 120, 1, 100000,
  );
  const globalLimit = boundedInteger(
    env[isAi ? 'PUBLIC_AI_GLOBAL_DAILY_LIMIT' : 'PUBLIC_FOOTBALL_GLOBAL_DAILY_LIMIT'],
    isAi ? 1200 : 30000, 1, 1000000,
  );
  const maxConcurrent = boundedInteger(
    env[isAi ? 'PUBLIC_AI_MAX_CONCURRENT' : 'PUBLIC_FOOTBALL_MAX_CONCURRENT'],
    isAi ? 6 : 20, 1, 1000,
  );

  const identities = new Map();
  let globalStart = 0;
  let globalCalls = 0;
  let inFlight = 0;

  function denied(res, status, code, retryAfter) {
    if (retryAfter > 0) res.set('Retry-After', String(retryAfter));
    res.set('Cache-Control', 'no-store');
    return res.status(status).json({
      success: false,
      code,
      error: status === 429
        ? 'Troppe richieste. Riprova tra poco.'
        : status === 401
        ? 'Credenziale mobile non valida o mancante.'
        : 'Servizio momentaneamente non disponibile.',
    });
  }

  function takeSlot(identity, timestamp) {
    if (timestamp - globalStart >= globalPeriod || timestamp < globalStart) {
      globalStart = timestamp;
      globalCalls = 0;
    }
    if (globalCalls >= globalLimit) {
      return {retry: Math.max(1, Math.ceil(
        (globalPeriod - (timestamp - globalStart)) / 1000,
      ))};
    }

    let record = identities.get(identity);
    if (!record || timestamp - record.start >= clientPeriod ||
        timestamp < record.start) {
      record = {start: timestamp, calls: 0};
      if (!identities.has(identity) && identities.size >= MAX_IDENTITIES) {
        // Avoid unbounded memory allocation from arbitrary client identities.
        for (const [key, candidate] of identities.entries()) {
          if (timestamp - candidate.start >= clientPeriod) identities.delete(key);
        }
        if (identities.size >= MAX_IDENTITIES) {
          identities.delete(identities.keys().next().value);
        }
      }
      identities.set(identity, record);
    }
    if (record.calls >= perClientLimit) {
      return {retry: Math.max(1, Math.ceil(
        (clientPeriod - (timestamp - record.start)) / 1000,
      ))};
    }
    if (inFlight >= maxConcurrent) return {retry: 5};

    record.calls++;
    globalCalls++;
    inFlight++;
    return {release: true};
  }

  return async function publicApiGuard(req, res, next) {
    let identity;
    if (tokenMode === 'require') {
      if (typeof authenticate !== 'function') {
        return denied(res, 503, 'PUBLIC_API_AUTH_NOT_READY', 0);
      }
      const match = MOBILE_BEARER.exec(req.get('authorization') || '');
      if (!match) return denied(res, 401, 'PUBLIC_API_AUTH_REQUIRED', 0);
      try {
        const clientId = await authenticate(match[1]);
        if (!clientId) return denied(res, 401, 'PUBLIC_API_AUTH_DENIED', 0);
        identity = 'mobile:' + String(clientId);
      } catch (_) {
        return denied(res, 503, 'PUBLIC_API_AUTH_UNAVAILABLE', 0);
      }
    } else {
      // No unverified device IDs or headers may create extra rate buckets.
      identity = 'ip:' + String(req.ip || req.socket?.remoteAddress || 'unknown');
    }

    const result = takeSlot(identity, Number(now()));
    if (!result.release) {
      return denied(res, 429, isAi ? 'AI_RATE_LIMITED' : 'FOOTBALL_RATE_LIMITED', result.retry);
    }
    let released = false;
    const release = () => {
      if (!released) {
        released = true;
        inFlight = Math.max(0, inFlight - 1);
      }
    };
    res.once('finish', release);
    res.once('close', release);
    return next();
  };
}

module.exports = {
  createPublicApiGuard,
  createLearningMobileAuthenticator,
};
