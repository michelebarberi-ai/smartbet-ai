'use strict';

// B73: morning digest reuses the existing central SmartBet /football/fixtures
// proxy, so we do NOT introduce a second API-FOOTBALL credential, billing
// channel or rapid burst of calls from the free Render learning service.
const DAY=/^\d{4}-\d{2}-\d{2}$/;
const DEFAULT_ORIGIN='https://smartbet-ai-y6gw.onrender.com';
const TTL=60*60*1000;
let cached=null;
let pending=null;

async function fetchDailyFixtures(dayKey,{fetchImpl=fetch,now=Date.now,
    origin=DEFAULT_ORIGIN}={}) {
  if (!DAY.test(dayKey || '')) throw new TypeError('Invalid Rome calendar date');
  // Avoid allowing a user-controlled hostname, DNS rebinding or proxy redirects.
  if (origin !== DEFAULT_ORIGIN) throw new TypeError('Untrusted calendar origin');
  const stamp=now();
  if (cached && cached.dayKey===dayKey && stamp<cached.expiresAt) return cached.value;
  if (pending && pending.dayKey===dayKey) return pending.promise;
  const url=new URL('/football/fixtures',origin);
  url.searchParams.set('date',dayKey);
  url.searchParams.set('timezone','Europe/Rome');
  const promise=(async()=>{
    const reply=await fetchImpl(url,{
      method:'GET',redirect:'error',
      headers:{Accept:'application/json'},
      signal:AbortSignal.timeout(12000),
    });
    if (!reply.ok) throw new Error('Fixture proxy unavailable');
    const result=await reply.json();
    const errors=result?.errors;
    if (!Array.isArray(result?.response) ||
        (Array.isArray(errors) && errors.length>0) ||
        (errors && !Array.isArray(errors) && Object.keys(errors).length>0)) {
      throw new Error('Fixture feed invalid or rate limited');
    }
    cached={dayKey,expiresAt:now()+TTL,value:result};
    return result;
  })();
  pending={dayKey,promise};
  try{return await promise;}
  finally{if(pending?.promise===promise)pending=null;}
}

module.exports={fetchDailyFixtures};
