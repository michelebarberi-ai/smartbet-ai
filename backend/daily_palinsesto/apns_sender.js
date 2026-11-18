'use strict';

// B72: APNs alert for the morning fixture calendar. Independent of the
// retired automatic coupon scheduler and coupon-ready push flags.
const {createProviderToken, requestApns} = require('../auto_coupon/apns_provider');
const {digestApnsPayload} = require('./digest');

const DEVICE_TOKEN = /^[0-9a-fA-F]{64}$/;
const APP_ID = /^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;
const ID = /^[A-Za-z0-9]{10}$/;

function digestPushReady(env=process.env) {
  return env.DAILY_PALINSESTO_PUSH_ENABLED === 'true' &&
    ['production','sandbox'].includes(env.APNS_ENVIRONMENT) &&
    ID.test(env.APNS_KEY_ID || '') &&
    ID.test(env.APNS_TEAM_ID || '') &&
    APP_ID.test(env.APNS_BUNDLE_ID || '') &&
    typeof env.APNS_PRIVATE_KEY_BASE64 === 'string' &&
    env.APNS_PRIVATE_KEY_BASE64.length > 0;
}

async function sendDailyPalinsestoPush({
  digest, deviceToken, env=process.env, now=()=>new Date(),
  transport=requestApns,
}={}) {
  if (!digestPushReady(env)) return {status:'disabled'};
  if (!DEVICE_TOKEN.test(deviceToken || '')) return {status:'invalid_device_token'};
  let payload;
  try { payload=digestApnsPayload(digest); }
  catch (_) {return {status:'invalid_digest'};}
  const date=now();
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) {
    return {status:'invalid_clock'};
  }
  const unix=Math.floor(date.getTime()/1000);
  try {
    const signingKey=Buffer.from(env.APNS_PRIVATE_KEY_BASE64,'base64').toString('utf8');
    const jwt=createProviderToken({
      keyId:env.APNS_KEY_ID,teamId:env.APNS_TEAM_ID,
      privateKey:signingKey,issuedAt:unix,
    });
    const response=await transport({
      origin:env.APNS_ENVIRONMENT === 'production'
        ? 'https://api.push.apple.com'
        : 'https://api.sandbox.push.apple.com',
      headers:{
        ':method':'POST',
        ':path':`/3/device/${deviceToken.toLowerCase()}`,
        authorization:`bearer ${jwt}`,
        'apns-topic':env.APNS_BUNDLE_ID,
        'apns-push-type':'alert',
        'apns-priority':'10',
        // Repeated jobs never stack multiple notices for the same date.
        'apns-collapse-id':`palinsesto-${digest.dayKey}`,
        'apns-expiration':String(unix+7200),
        'content-type':'application/json',
      },
      payload,
    });
    if (response?.status===200) return {status:'accepted_by_apns'};
    if (response?.status===410) return {status:'unregistered_device'};
    return {status:'rejected_by_apns',httpStatus:response?.status};
  } catch (_) {
    // Never echo token, APNs key material, private URLs, or raw responses.
    return {status:'transport_error'};
  }
}

module.exports={digestPushReady,sendDailyPalinsestoPush};
