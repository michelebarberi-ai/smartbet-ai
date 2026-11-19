'use strict';

const {romeDayKey} = require('./rome_clock');
const {normalizeFixtureDigest} = require('./digest');
const {sendDailyPalinsestoPush,digestPushReady} = require('./apns_sender');
const {decryptDeviceToken} = require('../auto_coupon/device_registration');

function romeMinutes(now) {
  if (!(now instanceof Date) || !Number.isFinite(now.getTime())) {
    throw new TypeError('Invalid scheduling instant');
  }
  const parts=new Intl.DateTimeFormat('en-GB', {
    timeZone:'Europe/Rome',hour:'2-digit',minute:'2-digit',hourCycle:'h23',
  }).formatToParts(now);
  const values=Object.fromEntries(parts.map(x=>[x.type,x.value]));
  return Number(values.hour)*60+Number(values.minute);
}

async function dispatchDailyPalinsesto({
  repository, fetchDailyFixtures, env=process.env,
  now=()=>new Date(), send=sendDailyPalinsestoPush,
  decrypt=decryptDeviceToken, limit=20, afterSubjectHash=null,
}={}) {
  if (!digestPushReady(env)) return {status:'disabled'};
  if (!repository || typeof repository.listDue!=='function' ||
      typeof repository.claim!=='function' || typeof repository.read!=='function' ||
      typeof repository.finish!=='function' ||
      typeof fetchDailyFixtures!=='function' ||
      !/^[0-9a-fA-F]{64}$/.test(env.DAILY_PALINSESTO_PUSH_TOKEN_ENCRYPTION_KEY||'')) {
    return {status:'unconfigured'};
  }
  const instant=now();
  const dayKey=romeDayKey(instant);
  const minuteOfDay=romeMinutes(instant);
  if (minuteOfDay>=720) return {status:'past_morning',dayKey};
  const candidates=await repository.listDue({
    dayKey,minuteOfDay,now:instant,limit,afterSubjectHash,
  });
  if (!candidates.length) return {status:'checked',dayKey,checked:0,
    sent:0,retry:0,skipped:0,nextCursor:null};

  // Exactly ONE read for the entire batch, never one request per subscriber.
  // On 429/503 or malformed feed, no claims and no invented "0 fixtures".
  let digest;
  try {
    const providerData=await fetchDailyFixtures(dayKey);
    digest=normalizeFixtureDigest(providerData,{dayKey,now:instant});
  } catch (_) {
    return {status:'feed_unavailable',dayKey,checked:0};
  }

  let sent=0,retry=0,skipped=0;
  for (const item of candidates) {
    const subjectHash=item?.subjectHash;
    if (!/^[0-9a-f]{64}$/.test(subjectHash||'')) {
      skipped++;continue;
    }
    const claim=await repository.claim({subjectHash,dayKey,now:instant});
    if (!claim) {skipped++;continue;}
    let status='retry';
    try {
      const device=await repository.read(subjectHash);
      if (!device) status='unregistered';
      else if (device.environment!==env.APNS_ENVIRONMENT) status='retry';
      else {
        const deviceToken=decrypt({record:device,subjectHash,
          keyHex:env.DAILY_PALINSESTO_PUSH_TOKEN_ENCRYPTION_KEY});
        const result=await send({
          digest,deviceToken,env,now:()=>instant,
        });
        if (result?.status==='accepted_by_apns') status='sent';
        else if (result?.status==='unregistered_device' ||
                 result?.status==='invalid_device_token') status='unregistered';
        else status='retry';
      }
    } catch (_) {
      status='retry';
    }
    const finished=await repository.finish({
      subjectHash,dayKey,lockToken:claim.lockToken,now:instant,status,
    });
    if (!finished) {skipped++;continue;}
    if (status==='sent') sent++;
    else retry++;
  }
  return {status:'checked',dayKey,checked:candidates.length,
    sent,retry,skipped,
    nextCursor:candidates.length===limit ? candidates.at(-1).subjectHash : null};
}

module.exports={romeMinutes,dispatchDailyPalinsesto};
