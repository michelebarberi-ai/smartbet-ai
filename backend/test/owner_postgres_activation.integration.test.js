'use strict';

// Only runs when the GitHub Actions job supplies a throwaway PostgreSQL.
// Never connects to the user's Neon or production Render.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {Pool} = require('pg');
const {createOwnerAccessV2,PostgresOwnerStore} = require('../admin/owner_access_v2');
const {decodeBase32,totpForStep} = require('../admin/owner_mfa_staging');

const url = process.env.B61_TEST_DATABASE_URL;

test('B61: persistent email→TOTP setup and anti-replay survive new store instances',
    {skip: !url}, async () => {
  const pool = new Pool({connectionString:url});
  try {
    const ddl=fs.readFileSync(
      path.join(__dirname,'../admin/migrations/b61_owner_identity_v1.sql'),
      'utf8',
    );
    await pool.query(ddl);
    const base = new PostgresOwnerStore(pool);
    const messages=[];
    const environment={
      GOALVDLINE_OWNER_ACCESS_V2_ENABLED:'true',
      GOALVDLINE_OWNER_SETUP_HMAC_KEY:'integration-only-key-not-production-and-not-shared',
      GOALVDLINE_OWNER_AES256_KEY_B64:Buffer.alloc(32,8).toString('base64'),
      GOALVDLINE_OWNER_RECOVERY_EMAIL:'test-verified@example.invalid',
    };
    let now=1800000000000;
    const clock=()=>now;
    const sender=async mail=>messages.push(mail);
    const auth=createOwnerAccessV2({store:base,env:environment,clock,
      emailSender:sender});
    assert.equal((await auth.requestEmail()).status,202);
    assert.equal(messages.length,1);
    const ticket=(await auth.verifyEmail(messages[0].code)).ticket;
    const seed=(await auth.startTotp(ticket)).manualKey;
    const password='A long integration-test-only owner password';
    const code=totpForStep(decodeBase32(seed),Math.floor(now/30000));
    assert.equal((await auth.finishEnrollment(ticket,password,code)).status,200);

    // This is a new service object using the same database state.
    const restarted=createOwnerAccessV2({
      store:new PostgresOwnerStore(pool),env:environment,clock,
      emailSender:sender,
    });
    assert.equal((await restarted.status()).activated,true);
    assert.equal((await restarted.login(password,code)).status,401);
    now+=31000;
    const next=totpForStep(decodeBase32(seed),Math.floor(now/30000));
    const login=await restarted.login(password,next);
    assert.equal(login.status,200);
    assert.equal((await restarted.session(login.token)),true);

    const restartedAgain=createOwnerAccessV2({
      store:new PostgresOwnerStore(pool),env:environment,clock,
      emailSender:sender,
    });
    assert.equal((await restartedAgain.session(login.token)),true);
    assert.equal((await restartedAgain.logout(login.token)),true);
    assert.equal((await restarted.session(login.token)),false);
  } finally {
    await pool.end();
  }
});
