'use strict';

// GoalVdLine B61: first owner enrollment with verified fixed server email,
// scrypt password and server-generated encrypted RFC6238 TOTP secret.
// NO owner account can be self-asserted by a client-supplied email.
// Disabled by default; requires approved Neon schema and mail sender.
// Existing LEARNING_ADMIN_TOKEN remains server-only and distinct.

const crypto = require('node:crypto');
const {Pool} = require('pg');
const {createOwnerRecoverySender} = require('./owner_recovery_sender');
const {
  decodeBase32, findTotpStep, makeScryptHash, checkScryptPassword,
} = require('./owner_mfa_staging');

const CODE_LIFETIME = 10 * 60 * 1000;
const TICKET_LIFETIME = 10 * 60 * 1000;
const SESSION_LIFETIME = 15 * 60 * 1000;
const LOCK_LIFETIME = 15 * 60 * 1000;
const HOUR = 60 * 60 * 1000;
const REQUEST_GAP = 60 * 1000;
const TOKEN_REGEX = /^[A-Za-z0-9_-]{43}$/;

function base32Encode(buffer) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let carry = 0;
  let bits = 0;
  let out = '';
  for (const v of buffer) {
    carry = (carry << 8) | v;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += alphabet[(carry >>> bits) & 31];
      carry &= (1 << bits) - 1;
    }
  }
  if (bits) out += alphabet[(carry << (5 - bits)) & 31];
  return out;
}

function secureEqualHex(a, b) {
  if (!/^[0-9a-f]{64}$/.test(a || '') || !/^[0-9a-f]{64}$/.test(b || '')) {
    return false;
  }
  return crypto.timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}

function keyFromEnv(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(value)) {
    return null;
  }
  const key = Buffer.from(value, 'base64');
  return key.length === 32 && key.toString('base64') === value ? key : null;
}

function encryptTotp(secret, key) {
  if (!Buffer.isBuffer(secret) || secret.length !== 20 || !Buffer.isBuffer(key) ||
      key.length !== 32) throw new TypeError('Invalid TOTP encryption');
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const data = Buffer.concat([cipher.update(secret), cipher.final()]);
  return {
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    data: data.toString('base64'),
  };
}

function decryptTotp(enc, key) {
  if (!enc || typeof enc !== 'object') throw new Error('TOTP missing');
  const iv = Buffer.from(enc.iv || '', 'base64');
  const tag = Buffer.from(enc.tag || '', 'base64');
  const data = Buffer.from(enc.data || '', 'base64');
  if (iv.length !== 12 || tag.length !== 16 || data.length !== 20) {
    throw new Error('Encrypted TOTP invalid');
  }
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const clear = Buffer.concat([decipher.update(data), decipher.final()]);
  if (clear.length !== 20) throw new Error('Bad TOTP secret');
  return clear;
}

function digest(key, purpose, value) {
  return crypto.createHmac('sha256', key).update(purpose + ':' + value).digest('hex');
}

function parseBearer(req) {
  const value = typeof req.get === 'function' ? req.get('authorization') : '';
  const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(value || '');
  return match ? match[1] : null;
}

// Persisted, transactional singleton state. Each mutation acquires a row
// lock: multiple Render instances cannot issue two owner accounts.
class PostgresOwnerStore {
  constructor(pool) { this.pool = pool; }

  async transact(callback) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row = await client.query(
        'SELECT state FROM public.sb_owner_account_v1 WHERE id=1 FOR UPDATE',
      );
      if (row.rows.length !== 1) throw new Error('Owner schema not migrated');
      const state = row.rows[0].state || {};
      const result = await callback(state, client);
      await client.query(
        'UPDATE public.sb_owner_account_v1 SET state=$1::jsonb, updated_at=now() WHERE id=1',
        [JSON.stringify(state)],
      );
      await client.query('COMMIT');
      return result;
    } catch (err) {
      try { await client.query('ROLLBACK'); } catch (_) { /* fail closed */ }
      throw err;
    } finally {
      client.release();
    }
  }

  async hasSession(tokenHash) {
    const result = await this.pool.query(
      'SELECT 1 FROM public.sb_owner_sessions_v1 WHERE token_digest=$1 AND expires_at > now()',
      [tokenHash],
    );
    return result.rows.length === 1;
  }

  async dropSession(tokenHash) {
    await this.pool.query(
      'DELETE FROM public.sb_owner_sessions_v1 WHERE token_digest=$1',
      [tokenHash],
    );
  }
}

function createOwnerAccessV2({
  env = process.env, store = null, emailSender = null,
  clock = () => Date.now(), randomBytes = crypto.randomBytes,
} = {}) {
  const key = keyFromEnv(env.GOALVDLINE_OWNER_AES256_KEY_B64);
  const hmacKey = env.GOALVDLINE_OWNER_SETUP_HMAC_KEY;
  const address = env.GOALVDLINE_OWNER_RECOVERY_EMAIL;
  const sender = emailSender || createOwnerRecoverySender({env});
  const enabled = env.GOALVDLINE_OWNER_ACCESS_V2_ENABLED === 'true' &&
    !!store && !!key &&
    typeof hmacKey === 'string' && hmacKey.length >= 32 &&
    typeof address === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address) &&
    typeof sender === 'function';

  const emailHash = code => digest(hmacKey, 'email-activation', code);
  const ticketHash = token => digest(hmacKey, 'owner-activation-ticket', token);
  const sessionHash = token => crypto.createHash('sha256').update(token).digest('hex');
  const fail = (status = 401) => ({status, success:false});

  async function status() {
    if (!enabled) return {status:503, ready:false};
    try {
      return await store.transact(async state => ({
        status:200, ready:true, activated:state.activated === true,
      }));
    } catch (_) {
      return {status:503, ready:false};
    }
  }

  async function requestEmail() {
    if (!enabled) return fail(503);
    let emailCode;
    try {
      const result = await store.transact(async state => {
        const now = clock();
        if (state.activated === true) return fail(409);
        if (!Number.isFinite(now) || now <= 0) return fail(503);
        if (now >= (state.emailWindowUntil || 0)) {
          state.emailWindowUntil = now + HOUR;
          state.emailRequests = 0;
        }
        if ((state.emailRequests || 0) >= 3 ||
            now - (state.emailRequestedAt || 0) < REQUEST_GAP) {
          return fail(429);
        }
        emailCode = String(crypto.randomInt(100000000)).padStart(8, '0');
        state.emailRequests = (state.emailRequests || 0) + 1;
        state.emailRequestedAt = now;
        state.emailDigest = emailHash(emailCode);
        state.emailExpires = now + CODE_LIFETIME;
        state.emailFailures = 0;
        state.ticketDigest = null;
        state.pendingTotp = null;
        return {status:202, success:true};
      });
      if (result.status !== 202) return result;
      try {
        await sender({to:address, code:emailCode, expiresInMinutes:10, purpose:'activation'});
      } catch (_) {
        // Do not log email, code, provider credentials, or recipient.
        return fail(503);
      }
      return result;
    } catch (_) { return fail(503); }
    finally { emailCode = null; }
  }

  async function verifyEmail(code) {
    if (!enabled) return fail(503);
    if (typeof code !== 'string' || !/^\d{8}$/.test(code)) return fail(400);
    try {
      return await store.transact(async state => {
        const now = clock();
        if (state.activated === true) return fail(409);
        if (now >= (state.emailExpires || 0) ||
            (state.emailFailures || 0) >= 5 ||
            !secureEqualHex(state.emailDigest, emailHash(code))) {
          state.emailFailures = (state.emailFailures || 0) + 1;
          if (state.emailFailures >= 5) {
            state.emailDigest = null;
            state.emailExpires = 0;
          }
          return fail();
        }
        state.emailDigest = null;
        state.emailExpires = 0;
        state.emailFailures = 0;
        const ticket = randomBytes(32).toString('base64url');
        state.ticketDigest = ticketHash(ticket);
        state.ticketExpires = now + TICKET_LIFETIME;
        return {status:200, success:true, ticket, expiresInSeconds:600};
      });
    } catch (_) { return fail(503); }
  }

  function ticketIsValid(state, ticket, now) {
    return typeof ticket === 'string' && TOKEN_REGEX.test(ticket) &&
      now < (state.ticketExpires || 0) &&
      secureEqualHex(state.ticketDigest, ticketHash(ticket));
  }

  async function startTotp(ticket) {
    if (!enabled) return fail(503);
    try {
      return await store.transact(async state => {
        const now = clock();
        if (state.activated === true) return fail(409);
        if (!ticketIsValid(state,ticket,now)) return fail();
        const seed = randomBytes(20);
        const base32 = base32Encode(seed);
        state.pendingTotp = encryptTotp(seed,key);
        state.pendingTotpFailures = 0;
        const label = encodeURIComponent('GoalVdLine:' + address);
        const uri = 'otpauth://totp/' + label +
          '?secret=' + base32 + '&issuer=GoalVdLine&digits=6&period=30';
        // Returned only after fixed-email verification, never on status.
        return {status:200, success:true, manualKey:base32, otpAuthUri:uri};
      });
    } catch (_) { return fail(503); }
  }

  async function finishEnrollment(ticket, password, code) {
    if (!enabled) return fail(503);
    if (typeof password !== 'string' || password.length < 16 ||
        password.length > 256 || typeof code !== 'string' ||
        !/^\d{6}$/.test(code)) return fail(400);
    try {
      return await store.transact(async state => {
        const now = clock();
        if (state.activated === true) return fail(409);
        if (!ticketIsValid(state,ticket,now) || !state.pendingTotp ||
            (state.pendingTotpFailures || 0) >= 5) return fail();
        let secret;
        try { secret = decryptTotp(state.pendingTotp,key); }
        catch (_) { return fail(503); }
        const step = findTotpStep(secret,code,now);
        if (step === null) {
          state.pendingTotpFailures = (state.pendingTotpFailures || 0) + 1;
          if (state.pendingTotpFailures >= 5) {
            state.ticketDigest = null;
            state.pendingTotp = null;
          }
          return fail();
        }
        state.passwordHash = makeScryptHash(password);
        state.totp = state.pendingTotp;
        state.lastTotpStep = step;
        state.activated = true;
        state.activatedAt = now;
        state.pendingTotp = null;
        state.pendingTotpFailures = 0;
        state.ticketDigest = null;
        state.ticketExpires = 0;
        state.emailDigest = null;
        return {status:200, success:true, activated:true};
      });
    } catch (_) { return fail(503); }
  }


  async function createSession(client, now) {
    const token = randomBytes(32).toString('base64url');
    await client.query(
      'INSERT INTO public.sb_owner_sessions_v1 (token_digest, expires_at) '+
      'VALUES ($1, to_timestamp($2 / 1000.0))',
      [sessionHash(token),now + SESSION_LIFETIME],
    );
    return {status:200, success:true, token, expiresInSeconds:900,
      scope:'owner-staging-login-only'};
  }

  const recoveryHash = code => digest(hmacKey, 'owner-email-recovery', code);

  async function requestRecovery(password) {
    if (!enabled) return fail(503);
    // Return the same success shape even if the password is wrong, to avoid
    // revealing whether the email account has been configured.
    if (typeof password !== 'string' || password.length > 256) return fail(400);
    let emailCode;
    try {
      const result = await store.transact(async state => {
        const now = clock();
        if (state.activated !== true) return fail(503);
        if (now < (state.loginLockUntil || 0)) return fail(429);
        if (now >= (state.recoveryWindowUntil || 0)) {
          state.recoveryWindowUntil = now + HOUR;
          state.recoveryRequests = 0;
        }
        if ((state.recoveryRequests || 0) >= 3 ||
            now - (state.recoveryRequestedAt || 0) < REQUEST_GAP) {
          return fail(429);
        }
        state.recoveryRequests = (state.recoveryRequests || 0) + 1;
        state.recoveryRequestedAt = now;
        if (!checkScryptPassword(password,state.passwordHash)) {
          return {status:202,success:true,delivery:false};
        }
        emailCode = String(crypto.randomInt(100000000)).padStart(8,'0');
        state.recoveryDigest = recoveryHash(emailCode);
        state.recoveryExpires = now + CODE_LIFETIME;
        state.recoveryFailures = 0;
        return {status:202,success:true,delivery:true};
      });
      if (result.status !== 202) return result;
      if (result.delivery === true) {
        try {
          await sender({to:address,code:emailCode,
            expiresInMinutes:10,purpose:'recovery'});
        } catch (_) {
          // The same accepted response is sent even for provider failures.
        }
      }
      return {status:202,success:true};
    } catch (_) { return fail(503); }
    finally { emailCode = null; }
  }

  async function loginByRecovery(password, code) {
    if (!enabled) return fail(503);
    if (typeof password !== 'string' || password.length > 256 ||
        typeof code !== 'string' || !/^\d{8}$/.test(code)) return fail(400);
    try {
      return await store.transact(async (state,client) => {
        const now = clock();
        if (state.activated !== true) return fail(503);
        if (now < (state.loginLockUntil || 0)) return fail(429);
        const passwordOk = checkScryptPassword(password,state.passwordHash);
        const codeOk = now < (state.recoveryExpires || 0) &&
          (state.recoveryFailures || 0) < 5 &&
          secureEqualHex(state.recoveryDigest,recoveryHash(code));
        if (!passwordOk || !codeOk) {
          state.recoveryFailures = (state.recoveryFailures || 0) + 1;
          state.loginFailures = (state.loginFailures || 0) + 1;
          if (state.recoveryFailures >= 5) {
            state.recoveryDigest = null;
            state.recoveryExpires = 0;
          }
          if (state.loginFailures >= 5) {
            state.loginFailures = 0;
            state.loginLockUntil = now + LOCK_LIFETIME;
            return fail(429);
          }
          return fail();
        }
        state.recoveryDigest = null; // Consume code atomically, once.
        state.recoveryExpires = 0;
        state.recoveryFailures = 0;
        state.loginFailures = 0;
        state.loginLockUntil = 0;
        return createSession(client,now);
      });
    } catch (_) { return fail(503); }
  }

  async function login(password, code) {
    if (!enabled) return fail(503);
    if (typeof password !== 'string' || password.length > 256 ||
        typeof code !== 'string' || !/^\d{6}$/.test(code)) return fail(400);
    try {
      return await store.transact(async (state, client) => {
        const now = clock();
        if (state.activated !== true) return fail(503);
        if (now < (state.loginLockUntil || 0)) return fail(429);
        let secret;
        try { secret = decryptTotp(state.totp,key); }
        catch (_) { return fail(503); }
        // Both factors are checked; response does not disclose the failing one.
        const goodPassword = checkScryptPassword(password,state.passwordHash);
        const step = findTotpStep(secret,code,now,state.lastTotpStep ?? -1);
        if (!goodPassword || step === null) {
          state.loginFailures = (state.loginFailures || 0) + 1;
          if (state.loginFailures >= 5) {
            state.loginFailures = 0;
            state.loginLockUntil = now + LOCK_LIFETIME;
            return fail(429);
          }
          return fail();
        }
        state.lastTotpStep = step;
        state.loginFailures = 0;
        state.loginLockUntil = 0;
        return createSession(client,now);
      });
    } catch (_) { return fail(503); }
  }

  async function session(token) {
    if (!enabled || typeof token !== 'string' || !TOKEN_REGEX.test(token)) {
      return false;
    }
    try { return await store.hasSession(sessionHash(token)); }
    catch (_) { return false; }
  }

  async function logout(token) {
    if (!enabled || typeof token !== 'string' || !TOKEN_REGEX.test(token)) {
      return false;
    }
    try {
      await store.dropSession(sessionHash(token));
      return true;
    } catch (_) { return false; }
  }

  return {
    enabled,status,requestEmail,verifyEmail,startTotp,finishEnrollment,
    login,requestRecovery,loginByRecovery,session,logout,
  };
}

function registerOwnerAccessV2(app, {env = process.env, store = null,
  clock, emailSender, poolFactory = opts => new Pool(opts)} = {}) {
  let pool;
  if (!store && env.GOALVDLINE_OWNER_ACCESS_V2_ENABLED === 'true' &&
      typeof env.DATABASE_URL === 'string' && env.DATABASE_URL.trim()) {
    pool = poolFactory({
      connectionString:env.DATABASE_URL,
      max:3, connectionTimeoutMillis:4000,
      idleTimeoutMillis:10000,
      ssl:env.LEARNING_PG_SSL === 'true' ? {rejectUnauthorized:true} : undefined,
    });
    store = new PostgresOwnerStore(pool);
  }
  const auth = createOwnerAccessV2({env,store,clock,emailSender});
  const send = (res,result) => {
    const {status,...body} = result;
    return res.status(status).json(body);
  };

  app.get('/owner/v1/setup/status', async (_req,res) =>
    send(res,await auth.status()));

  app.post('/owner/v1/setup/request', async (req,res) => {
    if (req.body === undefined || req.body === null ||
        typeof req.body !== 'object' || Array.isArray(req.body) ||
        Object.keys(req.body).length > 0) {
      return res.status(400).json({success:false});
    }
    send(res,await auth.requestEmail());
  });

  app.post('/owner/v1/setup/verify',async(req,res) => {
    const b=req.body;
    if (!b || typeof b !== 'object' || Array.isArray(b) ||
        Object.keys(b).join(',')!=='code') return res.status(400).json({success:false});
    send(res,await auth.verifyEmail(b.code));
  });

  app.post('/owner/v1/setup/totp/start',async(req,res) =>
    send(res,await auth.startTotp(parseBearer(req))));

  app.post('/owner/v1/setup/finish',async(req,res) => {
    const b=req.body;
    if (!b || typeof b !== 'object' || Array.isArray(b) ||
        Object.keys(b).sort().join(',')!=='code,password') {
      return res.status(400).json({success:false});
    }
    send(res,await auth.finishEnrollment(parseBearer(req),b.password,b.code));
  });

  app.post('/owner/v1/login',async(req,res) => {
    const b=req.body;
    if (!b || typeof b !== 'object' || Array.isArray(b) ||
        Object.keys(b).sort().join(',')!=='code,password') {
      return res.status(400).json({success:false});
    }
    send(res,await auth.login(b.password,b.code));
  });

  // Emergency recovery is PASSWORD + code delivered to the fixed email.
  // It cannot reset a password or enroll a different TOTP device.
  app.post('/owner/v1/recovery/request',async(req,res) => {
    const b=req.body;
    if (!b || typeof b !== 'object' || Array.isArray(b) ||
        Object.keys(b).join(',')!=='password') {
      return res.status(400).json({success:false});
    }
    send(res,await auth.requestRecovery(b.password));
  });

  app.post('/owner/v1/recovery/verify',async(req,res) => {
    const b=req.body;
    if (!b || typeof b !== 'object' || Array.isArray(b) ||
        Object.keys(b).sort().join(',')!=='code,password') {
      return res.status(400).json({success:false});
    }
    send(res,await auth.loginByRecovery(b.password,b.code));
  });

  app.get('/owner/v1/session',async(req,res) => {
    const active=await auth.session(parseBearer(req));
    res.status(active?200:401).json({success:active,active});
  });

  app.post('/owner/v1/logout',async(req,res) => {
    const active=await auth.session(parseBearer(req));
    if (active) await auth.logout(parseBearer(req));
    res.status(active?200:401).json({success:active});
  });

  return {auth,close:async()=>{if(pool)await pool.end();}};
}

module.exports = {
  base32Encode,encryptTotp,decryptTotp,keyFromEnv,PostgresOwnerStore,
  createOwnerAccessV2,registerOwnerAccessV2,
};
