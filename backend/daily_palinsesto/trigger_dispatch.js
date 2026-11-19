'use strict';

// The GitHub scheduled workflow calls ONLY the already-running learning API.
// No new Render worker/paid compute, and no coupon generator is ever invoked.
// This job runs only when the workflow is present on the default branch.
function validatedTarget(env=process.env) {
  const raw=env.DAILY_PALINSESTO_DISPATCH_URL;
  const token=env.DAILY_PALINSESTO_WORKER_TOKEN;
  if (!raw || typeof raw!=='string' || typeof token!=='string' ||
      token.length<32) return null;
  try {
    const target=new URL(raw);
    if (target.protocol!=='https:' || target.username || target.password ||
        target.search || target.hash ||
        target.pathname!=='/learning/v1/palinsesto/worker/dispatch' ||
        !target.hostname || target.hostname==='localhost' ||
        /^(?:127\.|10\.|192\.168\.|169\.254\.|0\.|::1$)/.test(target.hostname)) {
      return null;
    }
    return {url:target.toString(),token};
  } catch (_) {return null;}
}

async function run({env=process.env,fetchImpl=fetch,maxPages=50}={}) {
  const configured=validatedTarget(env);
  if (!configured) return {status:'disabled',pages:0};
  let nextCursor=null;
  let pages=0;
  let sent=0;
  for (;pages<maxPages;pages++) {
    const response=await fetchImpl(configured.url,{
      method:'POST',redirect:'error',
      headers:{
        'Content-Type':'application/json',
        'x-goalvdline-palinsesto-worker-token':configured.token,
      },
      body:JSON.stringify({limit:25,afterSubjectHash:nextCursor}),
      signal:AbortSignal.timeout(25000),
    });
    if (!response.ok) return {status:'server_unavailable',pages,sent};
    const result=await response.json();
    if (result?.status==='past_morning' || result?.status==='disabled') {
      return {status:result.status,pages,sent};
    }
    if (result?.status==='feed_unavailable') {
      return {status:'feed_unavailable',pages,sent};
    }
    if (result?.status!=='checked' || !Number.isInteger(result.sent) ||
        result.sent<0 || result.sent>25 ||
        (result.nextCursor!==null &&
          (typeof result.nextCursor!=='string' ||
            !/^[0-9a-f]{64}$/.test(result.nextCursor)))) {
      return {status:'invalid_worker_result',pages,sent};
    }
    sent+=result.sent;
    if (result.nextCursor===null) return {status:'completed',pages:pages+1,sent};
    if (nextCursor!==null && result.nextCursor<=nextCursor) {
      return {status:'invalid_cursor',pages,sent};
    }
    nextCursor=result.nextCursor;
  }
  return {status:'partial',pages,sent};
}

if (require.main===module) {
  run().then(result=>{
    // Only generic counts, never subscriptions, tokens or provider responses.
    console.log('Morning digest worker:',result.status,'pages:',result.pages,
      'accepted_by_apns:',result.sent||0);
    if (['server_unavailable','invalid_worker_result','invalid_cursor'].includes(result.status)) {
      process.exitCode=1;
    }
  }).catch(()=>{
    console.error('Morning digest worker unavailable');
    process.exitCode=1;
  });
}
module.exports={validatedTarget,run};
