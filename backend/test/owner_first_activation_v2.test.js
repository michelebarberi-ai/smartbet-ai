'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const express = require('express');
const {
  createOwnerAccessV2, registerOwnerAccessV2, base32Encode,
  encryptTotp, decryptTotp, keyFromEnv,
} = require('../admin/owner_access_v2');
const {decodeBase32, totpForStep} = require('../admin/owner_mfa_staging');

const ownerEmail = 'owner@example.test'; // TEST ADDRESS only, never production.
const password = 'A genuinely long and private owner passphrase';
const key = Buffer.alloc(32,7);
const env = {
  GOALVDLINE_OWNER_ACCESS_V2_ENABLED:'true',
  GOALVDLINE_OWNER_SETUP_HMAC_KEY:'unit-test-only-hmac-secret-with-enough-entropy',
  GOALVDLINE_OWNER_AES256_KEY_B64:key.toString('base64'),
  GOALVDLINE_OWNER_RECOVERY_EMAIL:ownerEmail,
};

class FakeOwnerStore {
  constructor() {
    this.state={};
    this.sessions=new Map();
  }
  async transact(fn) {
    const client={
      query:async (sql, params) => {
        if (!sql.includes('INSERT INTO public.sb_owner_sessions_v1')) {
          throw new Error('Unexpected SQL');
        }
        this.sessions.set(params[0],params[1]);
        return {rows:[]};
      },
    };
    return fn(this.state,client);
  }
  async hasSession(hash) {
    return (this.sessions.get(hash) || 0) > Date.now();
  }
  async dropSession(hash) {
    this.sessions.delete(hash);
  }
}

test('B61: disabled without a verified mail sender, encrypted keys and an owner store',
    async () => {
  const missing=createOwnerAccessV2({env,store:new FakeOwnerStore()});
  assert.equal(missing.enabled,false);
  assert.equal((await missing.status()).status,503);
  const badKey=createOwnerAccessV2({
    env:{...env,GOALVDLINE_OWNER_AES256_KEY_B64:'insecure'},
    store:new FakeOwnerStore(),emailSender:async()=>{},
  });
  assert.equal(badKey.enabled,false);
  assert.equal((await badKey.requestEmail()).status,503);
  assert.equal(keyFromEnv(env.GOALVDLINE_OWNER_AES256_KEY_B64).length,32);
});

test('B61: secrets are random, Base32 round trips and TOTP is encrypted at rest',
    () => {
  const secret=crypto.randomBytes(20);
  const encoded=base32Encode(secret);
  assert.equal(encoded.length,32);
  assert.deepEqual(decodeBase32(encoded),secret);
  const encrypted=encryptTotp(secret,key);
  assert.equal(encrypted.data.includes(encoded),false);
  assert.deepEqual(decryptTotp(encrypted,key),secret);
  assert.throws(()=>decryptTotp(encrypted,Buffer.alloc(32,1)));
});

test('B61: owner must verify fixed email before any TOTP seed or password setup',
    async () => {
  const sent=[];
  let now=1800000000000;
  const store=new FakeOwnerStore();
  const auth=createOwnerAccessV2({env,store,clock:()=>now,
    emailSender:async payload=>{sent.push(payload);}});
  assert.equal(auth.enabled,true);
  assert.deepEqual(await auth.status(),{status:200,ready:true,activated:false});
  assert.equal((await auth.startTotp('a'.repeat(43))).status,401);
  assert.equal((await auth.requestEmail()).status,202);
  assert.equal(sent.length,1);
  assert.equal(sent[0].to,ownerEmail);
  assert.equal(sent[0].purpose,'activation');
  assert.match(sent[0].code,/^\d{8}$/);
  assert.equal(store.state.emailDigest.includes(sent[0].code),false);
  assert.equal((await auth.requestEmail()).status,429);
  assert.equal((await auth.verifyEmail('0000000x')).status,400);
  const verify=await auth.verifyEmail(sent[0].code);
  assert.equal(verify.status,200);
  assert.match(verify.ticket,/^[A-Za-z0-9_-]{43}$/);
  assert.equal((await auth.verifyEmail(sent[0].code)).status,401);
  const pair=await auth.startTotp(verify.ticket);
  assert.equal(pair.status,200);
  assert.equal(pair.manualKey.length,32);
  assert.equal(pair.otpAuthUri.startsWith('otpauth://totp/'),true);
  assert.equal(pair.otpAuthUri.includes(ownerEmail),false); // URI must percent-encode @
  assert.equal(JSON.stringify(store.state).includes(pair.manualKey),false);

  // A password or code alone cannot finish the activation.
  assert.equal((await auth.finishEnrollment(verify.ticket,password,'222222')).status,401);
  const code=totpForStep(decodeBase32(pair.manualKey),Math.floor(now/30000));
  const final=await auth.finishEnrollment(verify.ticket,password,code);
  assert.equal(final.status,200);
  assert.equal(final.activated,true);
  assert.equal(store.state.activated,true);
  assert.equal(JSON.stringify(store.state).includes(password),false);
  assert.equal(JSON.stringify(store.state).includes(pair.manualKey),false);
  assert.equal(store.state.pendingTotp,null);
  assert.equal((await auth.requestEmail()).status,409);
  assert.equal((await auth.finishEnrollment(verify.ticket,password,code)).status,409);
  assert.equal((await auth.status()).activated,true);

  // The code consumed by setup is not valid for login (TOTP replay).
  assert.equal((await auth.login(password,code)).status,401);
  now+=30001;
  const fresh=totpForStep(decodeBase32(pair.manualKey),Math.floor(now/30000));
  const login=await auth.login(password,fresh);
  assert.equal(login.status,200);
  assert.equal(login.scope,'owner-staging-login-only'); // Not global admin role!
  assert.equal(login.expiresInSeconds,900);
  assert.equal(login.token.length,43);
  // Session uses hashed token rather than retaining it in plaintext.
  assert.equal(store.sessions.has(login.token),false);
  const digest=crypto.createHash('sha256').update(login.token).digest('hex');
  assert.equal(store.sessions.has(digest),true);
  assert.equal((await auth.session(login.token)),true);
  assert.equal((await auth.session('b'.repeat(43))),false);
  assert.equal((await auth.logout(login.token)),true);
  assert.equal((await auth.session(login.token)),false);
});

test('B61: email OTP expires and repeated errors exhaust its verification attempts',
    async () => {
  let now=1800000000000;
  const sent=[];
  const auth=createOwnerAccessV2({
    env,store:new FakeOwnerStore(),clock:()=>now,
    emailSender:async payload=>sent.push(payload),
  });
  assert.equal((await auth.requestEmail()).status,202);
  const wrong='11111111'===sent[0].code?'22222222':'11111111';
  for(let i=0;i<5;i++){
    assert.equal((await auth.verifyEmail(wrong)).status,401);
  }
  assert.equal((await auth.verifyEmail(sent[0].code)).status,401);
  now+=3600000;
  assert.equal((await auth.requestEmail()).status,202);
  now+=600001;
  assert.equal((await auth.verifyEmail(sent[1].code)).status,401);
});

test('B61: setup routes are fail-closed and never accept a client email field',
    async () => {
  const sent=[];
  const app=express();
  app.use(express.json());
  const store=new FakeOwnerStore();
  registerOwnerAccessV2(app,{env,store,clock:()=>1800000000000,
    emailSender:async payload=>sent.push(payload)});
  const server=app.listen(0,'127.0.0.1');
  try {
    await new Promise(ok=>server.once('listening',ok));
    const origin='http://127.0.0.1:'+server.address().port;
    const status=await fetch(origin+'/owner/v1/setup/status');
    assert.deepEqual(await status.json(),{ready:true,activated:false});
    const invalid=await fetch(origin+'/owner/v1/setup/request',{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({email:'attacker@example.test'}),
    });
    assert.equal(invalid.status,400);
    const request=await fetch(origin+'/owner/v1/setup/request',{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:'{}',
    });
    assert.equal(request.status,202);
    assert.equal(sent[0].to,ownerEmail);
    const verified=await fetch(origin+'/owner/v1/setup/verify',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({code:sent[0].code}),
    });
    assert.equal(verified.status,200);
    const ticket=(await verified.json()).ticket;
    const denied=await fetch(origin+'/owner/v1/setup/totp/start',{
      method:'POST',headers:{'Content-Type':'application/json'},body:'{}',
    });
    assert.equal(denied.status,401);
    const granted=await fetch(origin+'/owner/v1/setup/totp/start',{
      method:'POST',
      headers:{'Content-Type':'application/json','Authorization':'Bearer '+ticket},
      body:'{}',
    });
    assert.equal(granted.status,200);
    const payload=await granted.json();
    assert.match(payload.manualKey,/^[A-Z2-7]{32}$/);
  } finally {
    await new Promise((resolve,reject)=>server.close(e=>e?reject(e):resolve()));
  }
});
