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
 * tokenMode: 'off' (default and backwards compatible), 'prefer' (valid
 * bearer tokens receive separate, verified-install budgets, older anonymous
 * iPhones receive stricter budgets), or 'require' (all clients authenticated).
 * Do not activate 'require' before app-wide credential provisioning.
 * This is a PER PROCESS budget, never a distributed spending guarantee.
 */
function createPublicApiGuard({
  env = process.env,
  now = () => Date.now(),
  authenticate = null,
  tokenMode = 'off',
  group = 'ai',
} = {}) {
  if (!['off', 'prefer', 'require'].includes(tokenMode)) {
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
  // These stricter anonymous budgets apply ONLY in transitional 'prefer'
  // mode. 'off' preserves the installed Build 64's existing behavior.
  const anonymousClientLimit = boundedInteger(
    env[isAi ? 'PUBLIC_AI_ANON_CLIENT_HOURLY_LIMIT' :
      'PUBLIC_FOOTBALL_ANON_CLIENT_MINUTE_LIMIT'],
    isAi ? 20 : 60, 1, 100000,
  );
  const anonymousGlobalLimit = boundedInteger(
    env[isAi ? 'PUBLIC_AI_ANON_GLOBAL_DAILY_LIMIT' :
      'PUBLIC_FOOTBALL_ANON_GLOBAL_DAILY_LIMIT'],
    isAi ? 200 : 5000, 1, 1000000,
  );
  const authAttemptLimit = boundedInteger(
    env.PUBLIC_MOBILE_AUTH_ATTEMPTS_PER_MINUTE,
    60, 1, 10000,
  );

  const identities = new Map();
  const authAttempts = new Map();
  let globalStart = 0;
  let globalCalls = 0;
  let anonymousCalls = 0;
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

  function retrySeconds(period, elapsed) {
    return Math.max(1, Math.ceil((period - elapsed) / 1000));
  }

  // Before a database lookup, bound malformed/random token attempts.
  // Never use untrusted X-Forwarded-For or a clientId from the request.
  function allowAuthAttempt(ip, timestamp) {
    let record = authAttempts.get(ip);
    if (!record || timestamp < record.start ||
        timestamp - record.start >= 60 * 1000) {
      if (!authAttempts.has(ip) && authAttempts.size >= MAX_IDENTITIES) {
        for (const [key, value] of authAttempts.entries()) {
          if (timestamp < value.start ||
              timestamp - value.start >= 60 * 1000) authAttempts.delete(key);
        }
        if (authAttempts.size >= MAX_IDENTITIES) return false;
      }
      record = {start: timestamp, calls: 0};
      authAttempts.set(ip, record);
    }
    if (record.calls >= authAttemptLimit) return false;
    record.calls++;
    return true;
  }

  function takeSlot(identity, timestamp, anonymous) {
    if (timestamp - globalStart >= globalPeriod || timestamp < globalStart) {
      globalStart = timestamp;
      globalCalls = 0;
      anonymousCalls = 0;
    }
    if (globalCalls >= globalLimit) {
      return {retry: retrySeconds(globalPeriod, timestamp - globalStart)};
    }
    if (anonymous && tokenMode === 'prefer' &&
        anonymousCalls >= anonymousGlobalLimit) {
      return {retry: retrySeconds(globalPeriod, timestamp - globalStart)};
    }

    let record = identities.get(identity);
    if (!record || timestamp - record.start >= clientPeriod ||
        timestamp < record.start) {
      if (!identities.has(identity) && identities.size >= MAX_IDENTITIES) {
        for (const [key, value] of identities.entries()) {
          if (timestamp < value.start ||
              timestamp - value.start >= clientPeriod) identities.delete(key);
        }
        // Do not evict an active identity: it would reset its quota.
        if (identities.size >= MAX_IDENTITIES) return {retry: 60};
      }
      record = {start: timestamp, calls: 0};
      identities.set(identity, record);
    }

    const activeLimit = anonymous && tokenMode === 'prefer'
      ? anonymousClientLimit : perClientLimit;
    if (record.calls >= activeLimit) {
      return {retry: retrySeconds(clientPeriod, timestamp - record.start)};
    }
    if (inFlight >= maxConcurrent) return {retry: 5};

    record.calls++;
    globalCalls++;
    if (anonymous) anonymousCalls++;
    inFlight++;
    return {release: true};
  }

  return async function publicApiGuard(req, res, next) {
    const ip = String(req.ip || req.socket?.remoteAddress || 'unknown');
    const header = req.get('authorization') || '';
    let identity = 'ip:' + ip;
    let anonymous = true;

    if (tokenMode === 'require' && typeof authenticate !== 'function') {
      return denied(res, 503, 'PUBLIC_API_AUTH_NOT_READY', 0);
    }
    if (tokenMode !== 'off') {
      if (header) {
        const match = MOBILE_BEARER.exec(header);
        if (!match) return denied(res, 401, 'PUBLIC_API_AUTH_REQUIRED', 0);
        if (typeof authenticate !== 'function') {
          return denied(res, 503, 'PUBLIC_API_AUTH_NOT_READY', 0);
        }
        if (!allowAuthAttempt(ip, Number(now()))) {
          return denied(res, 429, 'PUBLIC_API_AUTH_RATE_LIMITED', 60);
        }
        try {
          const clientId = await authenticate(match[1]);
          if (!clientId) return denied(res, 401, 'PUBLIC_API_AUTH_DENIED', 0);
          identity = 'mobile:' + String(clientId);
          anonymous = false;
        } catch (_) {
          return denied(res, 503, 'PUBLIC_API_AUTH_UNAVAILABLE', 0);
        }
      } else if (tokenMode === 'require') {
        return denied(res, 401, 'PUBLIC_API_AUTH_REQUIRED', 0);
      }
    }
    // If 'off': ignore client-supplied tokens entirely for budget identity.
    // If 'prefer': missing token gets anonymous-IP quota, never mobile quota.
    const result = takeSlot(identity, Number(now()), anonymous);
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
