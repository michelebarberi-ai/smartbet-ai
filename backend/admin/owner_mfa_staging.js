'use strict';

// B58 — OWNER MFA STAGING ONLY.
// No administrator identity/role is inferred from an app-side flag, email,
// saved device token, or public user profile. The legacy admin service token
// remains server-only and unchanged.
//
// This single-process prototype must NOT be deployed for owner/admin data
// access before shared replay/rate-limit/session storage and role authorization
// are implemented. Feature flag is OFF by default.

const crypto = require('node:crypto');

const WINDOW_MS = 15 * 60 * 1000;
const SESSION_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const MAX_SESSIONS = 3;

function decodeBase32(raw) {
  if (typeof raw !== 'string') return null;
  const value = raw.toUpperCase().replace(/=+$/, '');
  if (value.length < 32 || !/^[A-Z2-7]+$/.test(value)) return null;
  const bytes = [];
  let bits = 0;
  let accumulator = 0;
  for (const c of value) {
    const v = c.charCodeAt(0) >= 65 ? c.charCodeAt(0) - 65 : c.charCodeAt(0) - 50 + 26;
    accumulator = (accumulator << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((accumulator >>> bits) & 0xff);
      accumulator &= (1 << bits) - 1;
    }
  }
  if (bytes.length < 20) return null;
  return Buffer.from(bytes);
}

function totpForStep(secret, step) {
  if (!Buffer.isBuffer(secret) || secret.length < 20 ||
      !Number.isSafeInteger(step) || step < 0) {
    throw new TypeError('Invalid TOTP input');
  }
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const digest = crypto.createHmac('sha1', secret).update(counter).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const raw = ((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      (digest[offset + 3] & 0xff);
  return String(raw % 1000000).padStart(6, '0');
}

function findTotpStep(secret, code, millis, lastUsedStep = -1) {
  if (typeof code !== 'string' || !/^\d{6}$/.test(code) ||
      !Number.isFinite(millis) || millis < 0) return null;
  const current = Math.floor(millis / 30000);
  // One step of skew, but each time step may be used only ONCE.
  for (let d = -1; d <= 1; d++) {
    const step = current + d;
    if (step < 0 || step <= lastUsedStep) continue;
    const expected = Buffer.from(totpForStep(secret, step), 'ascii');
    if (crypto.timingSafeEqual(Buffer.from(code, 'ascii'), expected)) {
      return step;
    }
  }
  return null;
}

function parseScryptHash(serialized) {
  if (typeof serialized !== 'string') return null;
  const match = /^scrypt\$16384\$8\$1\$([0-9a-f]{64})\$([0-9a-f]{64})$/i.exec(serialized);
  if (!match) return null;
  return {salt: Buffer.from(match[1], 'hex'), digest: Buffer.from(match[2], 'hex')};
}

// Offline provisioning ONLY; no public endpoints are allowed to generate,
// reset, or expose TOTP secrets or password hashes.
function makeScryptHash(password, salt = crypto.randomBytes(32)) {
  if (typeof password !== 'string' || password.length < 16 ||
      password.length > 256 || !Buffer.isBuffer(salt) || salt.length !== 32) {
    throw new TypeError('Invalid password provisioning');
  }
  const digest = crypto.scryptSync(password, salt, 32, {
    N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024,
  });
  return 'scrypt$16384$8$1$' + salt.toString('hex') + '$' + digest.toString('hex');
}

function checkScryptPassword(password, serialized) {
  if (typeof password !== 'string' || password.length > 256 || password.length === 0) return false;
  const parsed = parseScryptHash(serialized);
  if (!parsed) return false;
  const got = crypto.scryptSync(password, parsed.salt, 32, {
    N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024,
  });
  return crypto.timingSafeEqual(got, parsed.digest);
}

function createOwnerMfa({env = process.env, clock = () => Date.now(), randomBytes = crypto.randomBytes, emailSender = null} = {}) {
  const secret = decodeBase32(env.GOALVDLINE_OWNER_TOTP_SECRET_BASE32);
  const passwordHash = env.GOALVDLINE_OWNER_PASSWORD_SCRYPT;
  const enabled = env.GOALVDLINE_OWNER_MFA_STAGING_ENABLED === 'true' &&
      !!parseScryptHash(passwordHash) && secret !== null;

  let lastUsedStep = -1;
  let attempts = 0;
  let lockUntil = 0;
  const sessions = new Map(); // sha256(token) => expiry (per-process only).
  // Optional recovery, disabled unless a VERIFIED owner mailbox and provider
  // credentials are installed. In-memory ONLY, not production ready.
  const recoveryEnabled = enabled &&
    env.GOALVDLINE_OWNER_RECOVERY_ENABLED === 'true' &&
    typeof env.GOALVDLINE_OWNER_RECOVERY_EMAIL === 'string' &&
    /^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(env.GOALVDLINE_OWNER_RECOVERY_EMAIL) &&
    typeof env.GOALVDLINE_OWNER_RECOVERY_HMAC_KEY === 'string' &&
    env.GOALVDLINE_OWNER_RECOVERY_HMAC_KEY.length >= 32 &&
    typeof emailSender === 'function';
  let recovery = null; // hashed 8-digit email OTP, expiry and attempt counter.
  let recoveryWindowUntil = 0;
  let recoveryRequests = 0;

  function createSession(now) {
    const token = randomBytes(32).toString('base64url');
    const hash = crypto.createHash('sha256').update(token).digest('hex');
    sessions.set(hash, now + SESSION_MS);
    while (sessions.size > MAX_SESSIONS) {
      sessions.delete(sessions.keys().next().value);
    }
    return {status: 200, token, expiresInSeconds: SESSION_MS / 1000};
  }

  function recoveryDigest(code) {
    return crypto.createHmac('sha256', env.GOALVDLINE_OWNER_RECOVERY_HMAC_KEY)
      .update('owner-recovery-v1:' + code).digest();
  }

  async function requestEmailRecovery(password) {
    if (!recoveryEnabled) return {status:503};
    const now = clock();
    if (now < lockUntil) return {status:429};
    if (now >= recoveryWindowUntil) {
      recoveryWindowUntil = now + 60 * 60 * 1000;
      recoveryRequests = 0;
    }
    if (recoveryRequests >= 3) return {status:429};
    recoveryRequests++;
    // Generic accepted response: no login-name/password enumeration.
    if (!checkScryptPassword(password, passwordHash)) return {status:202};
    const code = String(crypto.randomInt(100000000)).padStart(8, '0');
    recovery = {digest: recoveryDigest(code), expiry: now + 10 * 60 * 1000,
      attempts:0};
    try {
      await emailSender({
        to: env.GOALVDLINE_OWNER_RECOVERY_EMAIL,
        code,
        expiresInMinutes:10,
      });
    } catch (_) {
      recovery = null;
    }
    return {status:202};
  }

  function authenticateEmailRecovery(password, code) {
    if (!recoveryEnabled) return {status:503};
    const now = clock();
    if (now < lockUntil) return {status:429};
    const request = recovery;
    const isCode = typeof code === 'string' && /^\\d{8}$/.test(code);
    const goodCode = request !== null && now < request.expiry &&
      request.attempts < 5 && isCode &&
      crypto.timingSafeEqual(request.digest, recoveryDigest(code));
    const goodPassword = checkScryptPassword(password, passwordHash);
    if (!goodCode || !goodPassword) {
      if (request !== null) {
        request.attempts++;
        if (request.attempts >= 5) recovery = null;
      }
      attempts++;
      if (attempts >= MAX_ATTEMPTS) {
        attempts = 0;
        lockUntil = now + WINDOW_MS;
        return {status:429};
      }
      return {status:401};
    }
    recovery = null; // Consume email code BEFORE issuing any session.
    attempts = 0;
    return createSession(now);
  }

  function authenticate(password, code) {
    if (!enabled) return {status: 503, error: 'Accesso amministratore non configurato.'};
    const now = clock();
    if (!Number.isFinite(now) || now < 0) return {status: 503, error: 'Orologio non disponibile.'};
    if (now < lockUntil) return {status: 429, error: 'Troppi tentativi. Riprova più tardi.'};
    // Validate BOTH factors even if one fails, without revealing which.
    const goodPassword = checkScryptPassword(password, passwordHash);
    const step = findTotpStep(secret, code, now, lastUsedStep);
    if (!goodPassword || step === null) {
      attempts += 1;
      if (attempts >= MAX_ATTEMPTS) {
        lockUntil = now + WINDOW_MS;
        attempts = 0;
        return {status: 429, error: 'Troppi tentativi. Riprova più tardi.'};
      }
      return {status: 401, error: 'Credenziali non valide.'};
    }
    attempts = 0;
    lockUntil = 0;
    lastUsedStep = step;

    // Ephemeral random bearer session shared with verified email backup.
    return createSession(now);
  }

  function verifySession(token) {
    if (!enabled || typeof token !== 'string' ||
        !/^[A-Za-z0-9_-]{43}$/.test(token)) return false;
    const now = clock();
    const hash = crypto.createHash('sha256').update(token).digest('hex');
    const expires = sessions.get(hash);
    if (expires === undefined || now >= expires) {
      sessions.delete(hash);
      return false;
    }
    return true;
  }

  function revoke(token) {
    if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token)) return false;
    const hash = crypto.createHash('sha256').update(token).digest('hex');
    return sessions.delete(hash);
  }

  return {
    enabled, recoveryEnabled, authenticate, requestEmailRecovery,
    authenticateEmailRecovery, verifySession, revoke,
  };
}

function registerOwnerMfaStagingRoutes(app, {env = process.env, clock} = {}) {
  const auth = createOwnerMfa({env, clock});
  const readBearer = req => {
    const header = typeof req.get === 'function' ? req.get('authorization') : null;
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(header || '');
    return match ? match[1] : null;
  };

  // Explicit no-store responses. These are STAGING login endpoints only:
  // NO existing learning/admin route is granted access by this session yet.
  app.post('/owner/v1/login', (req, res) => {
    if (!auth.enabled) return res.status(503).json({success:false, error:'Accesso non configurato.'});
    const body = req.body;
    if (!body || typeof body !== 'object' || Array.isArray(body) ||
        Object.keys(body).sort().join(',') !== 'code,password') {
      return res.status(400).json({success:false,error:'Richiesta non valida.'});
    }
    const outcome = auth.authenticate(body.password, body.code);
    if (outcome.status !== 200) return res.status(outcome.status).json({
      success:false, error:outcome.error,
    });
    return res.status(200).json({
      success:true, token:outcome.token, expiresInSeconds:outcome.expiresInSeconds,
      // Not a server-side admin role grant.
      scope:'owner-staging-login-only',
    });
  });

  app.get('/owner/v1/session', (req,res) => {
    const authorized = auth.verifySession(readBearer(req));
    return res.status(authorized ? 200 : 401).json({
      success:authorized, active:authorized,
    });
  });
  app.post('/owner/v1/logout', (req,res) => {
    const token = readBearer(req);
    const ok = auth.verifySession(token);
    if (ok) auth.revoke(token);
    return res.status(ok ? 200 : 401).json({success:ok});
  });
  return auth;
}

module.exports = {
  decodeBase32, totpForStep, findTotpStep, makeScryptHash,
  checkScryptPassword, createOwnerMfa, registerOwnerMfaStagingRoutes,
};
