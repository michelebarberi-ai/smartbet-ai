'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createOwnerRecoverySender}=require('../admin/owner_recovery_sender');

const env={
  GOALVDLINE_OWNER_RECOVERY_ENABLED:'true',
  GOALVDLINE_OWNER_RECOVERY_EMAIL:'owner@example.test',
  GOALVDLINE_OWNER_RECOVERY_EMAIL_FROM:'onboarding@resend.dev',
  GOALVDLINE_OWNER_RECOVERY_RESEND_KEY:'re_only_for_unit_tests',
};

test('B61: Resend rejection logs HTTP status ONLY, without sensitive values',
    async()=>{
  const logs=[];
  const original=console.warn;
  console.warn=(...args)=>logs.push(args);
  try{
    const sender=createOwnerRecoverySender({
      env,
      fetchImpl:async()=>({status:403}),
    });
    const code='87654321';
    await assert.rejects(
      sender({to:env.GOALVDLINE_OWNER_RECOVERY_EMAIL,code,
        expiresInMinutes:10,purpose:'activation'}),
      /provider unavailable/,
    );
    assert.equal(logs.length,1);
    assert.deepEqual(logs[0],[
      'GoalVdLine owner mail provider HTTP status:',403,
    ]);
    const logged=JSON.stringify(logs);
    assert.equal(logged.includes(code),false);
    assert.equal(logged.includes(env.GOALVDLINE_OWNER_RECOVERY_EMAIL),false);
    assert.equal(logged.includes(env.GOALVDLINE_OWNER_RECOVERY_RESEND_KEY),false);
  } finally{
    console.warn=original;
  }
});

test('B61: successful Resend request does not produce additional logs',
    async()=>{
  const logs=[];
  const original=console.warn;
  console.warn=(...args)=>logs.push(args);
  try{
    const sender=createOwnerRecoverySender({
      env,fetchImpl:async()=>({status:201}),
    });
    await sender({to:env.GOALVDLINE_OWNER_RECOVERY_EMAIL,
      code:'12345678',expiresInMinutes:10,purpose:'activation'});
    assert.deepEqual(logs,[]);
  } finally{
    console.warn=original;
  }
});
