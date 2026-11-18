'use strict';

// A single calendar read, no odds endpoint, no betting or OpenAI execution.
const DAY=/^\d{4}-\d{2}-\d{2}$/;
const ORIGIN='https://v3.football.api-sports.io';
const CACHE_TTL=60*60*1000;
const dayCache=new Map();

async function fetchDailyFixtures(dayKey,{
  env=process.env,fetchImpl=fetch,now=Date.now,
}={}) {
  if (!DAY.test(dayKey||'')) throw new TypeError('Invalid Rome calendar date');
  const key=env.FOOTBALL_API_KEY;
  if (typeof key!=='string'||!key.trim()) {
    throw new Error('Daily calendar provider not configured');
  }
  const cached=dayCache.get(dayKey);
  const timestamp=now();
  if (cached && timestamp<cached.expiresAt) return cached.value;
  const url=new URL('/fixtures',ORIGIN);
  url.searchParams.set('date',dayKey);
  url.searchParams.set('timezone','Europe/Rome');
  const response=await fetchImpl(url,{
    method:'GET',
    headers:{'x-apisports-key':key,Accept:'application/json'},
    redirect:'error',signal:AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('Daily calendar provider unavailable');
  const result=await response.json();
  if (!Array.isArray(result?.response) ||
      (Array.isArray(result.errors) && result.errors.length>0) ||
      (result.errors && !Array.isArray(result.errors) &&
        Object.keys(result.errors).length>0)) {
    throw new Error('Daily calendar provider returned invalid data');
  }
  // Two Rome days maximum in cache, bounded small memory, no user data.
  dayCache.clear();
  dayCache.set(dayKey,{value:result,expiresAt:timestamp+CACHE_TTL});
  return result;
}

module.exports={fetchDailyFixtures};
