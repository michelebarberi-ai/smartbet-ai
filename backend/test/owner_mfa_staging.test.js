'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {
  decodeBase32, totpForStep, findTotpStep, makeScryptHash,
  checkScryptPassword, createOwnerMfa, registerOwnerMfaStagingRoutes,
} = require('../admin/owner_mfa_staging');

const BASE32 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'; // Public RFC test vector only.
const SECRET = decodeBase32(BASE32);
const PASSPHRASE = 'A demonstration passphrase with 24 characters';
const HASH = makeScryptHash(PASSPHRASE, Buffer.alloc(32, 9));
const config = {
  GOALVDLINE_OWNER_MFA_STAGING_ENABLED: 'true',
  GOALVDLINE_OWNER_TOTP_SECRET_BASE32: BASE32,
  GOALVDLINE_OWNER_PASSWORD_SCRYPT: HASH,
};

test('B58: TOTP matches RFC 6238 SHA1 6-digit truncation', () => {
  assert.equal(SECRET.toString('ascii'), '12345678901234567890');
  assert.equal(totpForStep(SECRET, 1), '287082');
  assert.equal(findTotpStep(SECRET, '287082', 59000), 1);
  assert.equal(findTotpStep(SECRET, '287082', 59000, 1), null);
  assert.equal(findTotpStep(SECRET, 287082, 59000), null);
  assert.equal(findTotpStep(SECRET, 'not-code', 59000), null);
});

test('B58: offline scrypt password hash rejects wrong passwords', () => {
  assert.match(HASH, /^scrypt\$16384\$8\$1\$/);
  assert.equal(checkScryptPassword(PASSPHRASE, HASH), true);
  assert.equal(checkScryptPassword('wrong secret', HASH), false);
  assert.equal(checkScryptPassword(PASSPHRASE, 'plaintext-not-valid'), false);
  assert.notEqual(HASH.includes(PASSPHRASE), true);
});

test('B58: owner login disabled by default and with incomplete secrets', () => {
  const off = createOwnerMfa({env: config === null ? {} : {...config,GOALVDLINE_OWNER_MFA_STAGING_ENABLED:'false'}});
  assert.equal(off.enabled, false);
  assert.equal(off.authenticate(PASSPHRASE, '287082').status, 503);
  const missing = createOwnerMfa({env:{GOALVDLINE_OWNER_MFA_STAGING_ENABLED:'true'}});
  assert.equal(missing.enabled,false);
  assert.equal(missing.authenticate('anything','123456').status,503);
});

test('B58: password plus TOTP issues 15-minute session without admin privileges', () => {
  let millis = 59000;
  const auth = createOwnerMfa({env:config,clock:()=>millis});
  const code = totpForStep(SECRET,Math.floor(millis/30000));
  const result = auth.authenticate(PASSPHRASE,code);
  assert.equal(result.status,200);
  assert.equal(result.expiresInSeconds,900);
  assert.match(result.token,/^[A-Za-z0-9_-]{43}$/);
  assert.equal(auth.verifySession(result.token),true);
  // OTP is single-use even when the correct password is known.
  assert.equal(auth.authenticate(PASSPHRASE,code).status,401);
  assert.equal(auth.verifySession('x'.repeat(43)),false);
  millis += 900001;
  assert.equal(auth.verifySession(result.token),false);
});

test('B58: 5 failed attempts rate-limit brute force attempts for 15 minutes', () => {
  let millis = 59000;
  const auth = createOwnerMfa({env:config,clock:()=>millis});
  const code = totpForStep(SECRET,1);
  for (let attempt=1;attempt<=4;attempt++) {
    assert.equal(auth.authenticate('incorrect passphrase',code).status,401);
  }
  assert.equal(auth.authenticate('incorrect passphrase',code).status,429);
  assert.equal(auth.authenticate(PASSPHRASE,code).status,429);
  millis+=900001;
  assert.equal(auth.authenticate(PASSPHRASE,totpForStep(SECRET,Math.floor(millis/30000))).status,200);
});

test('B58: revoke terminates only the specified short-lived session', () => {
  let millis=59000;
  const auth=createOwnerMfa({env:config,clock:()=>millis});
  const a=auth.authenticate(PASSPHRASE,totpForStep(SECRET,1));
  millis+=31000;
  const b=auth.authenticate(PASSPHRASE,totpForStep(SECRET,3));
  assert.equal(a.status,200);
  assert.equal(b.status,200);
  assert.equal(auth.revoke(a.token),true);
  assert.equal(auth.verifySession(a.token),false);
  assert.equal(auth.verifySession(b.token),true);
});

test('B58: staged routes expose only session status, no admin resource', async () => {
  const express = require('express');
  const app = express();
  app.use(express.json());
  app.disable('x-powered-by');
  const clock=()=>59000;
  registerOwnerMfaStagingRoutes(app,{env:config,clock});
  const server=app.listen(0,'127.0.0.1');
  try {
    await new Promise(resolve=>server.once('listening',resolve));
    const base='http://127.0.0.1:'+server.address().port;
    const pre=await fetch(base+'/owner/v1/session');
    assert.equal(pre.status,401);
    const bad=await fetch(base+'/owner/v1/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({password:PASSPHRASE,code:999999})});
    assert.equal(bad.status,401);
    const login=await fetch(base+'/owner/v1/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({password:PASSPHRASE,code:totpForStep(SECRET,1)})});
    assert.equal(login.status,200);
    const data=await login.json();
    assert.equal(data.scope,'owner-staging-login-only');
    assert.equal(JSON.stringify(data).includes(PASSPHRASE),false);
    assert.equal(JSON.stringify(data).includes(BASE32),false);
    const session=await fetch(base+'/owner/v1/session',{headers:{authorization:'Bearer '+data.token}});
    assert.equal(session.status,200);
    const nonAdmin=await fetch(base+'/learning/v1/summary',{headers:{authorization:'Bearer '+data.token}});
    assert.equal(nonAdmin.status,404);
    const logout=await fetch(base+'/owner/v1/logout',{method:'POST',headers:{authorization:'Bearer '+data.token}});
    assert.equal(logout.status,200);
    assert.equal((await fetch(base+'/owner/v1/session',{headers:{authorization:'Bearer '+data.token}})).status,401);
  } finally {
    await new Promise((resolve,reject)=>server.close(e=>e?reject(e):resolve()));
  }
});
