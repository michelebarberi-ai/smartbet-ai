'use strict';

// P15: secure, opt-in HTTP transport to a separately deployed instance of the
// *same* official engine used by the app. NOT a prediction engine. In particular
// no candidate selection, synthetic odds or probability calculation happens here.
const {validateGeneratedCoupon} = require('./daily_schedule');

const PROTOCOL = 'goalvdline-official-coupon-v1';
const MAX_RESPONSE_BYTES = 65536;
const REVISION_PATTERN = /^[a-f0-9]{7,40}$/;
const JOB_ID = /^[0-9a-f]{32}$/;
const POLL_INTERVAL_MS = 5000;
const MAX_POLLS = 240; // max 20 min: up to 15 fixtures may require more time

function officialEngineConfiguration(env = process.env) {
  if (env.AUTO_COUPON_OFFICIAL_ENGINE_ENABLED !== 'true') return null;
  const rawUrl = env.AUTO_COUPON_OFFICIAL_ENGINE_URL;
  const token = env.AUTO_COUPON_OFFICIAL_ENGINE_TOKEN;
  const revision = env.AUTO_COUPON_OFFICIAL_ENGINE_REVISION;
  if (typeof token !== 'string' || token.length < 32 ||
      typeof revision !== 'string' || !REVISION_PATTERN.test(revision)) return null;

  // P20.3D: a dedicated, explicit STAGING-ONLY path for an exact named Render
  // private service. This is plain HTTP on Render's *private* network, not
  // end-to-end TLS. Never allow general hostnames, IPs, public domains or a
  // caller-supplied path; keep the existing public HTTPS path unchanged.
  if (env.AUTO_COUPON_OFFICIAL_ENGINE_PRIVATE_RENDER_ENABLED === 'true') {
    if (rawUrl !== undefined && rawUrl !== '') return null;
    const hostport = env.AUTO_COUPON_OFFICIAL_ENGINE_HOSTPORT;
    if (typeof hostport !== 'string' ||
        !/^smartbet-b45-flutter-staging(?:-[a-z0-9]+)?:8799$/.test(hostport)) {
      return null;
    }
    return {url:`http://${hostport}/coupon/generate`, token, revision};
  }

  if (typeof rawUrl !== 'string') return null;
  let url;
  try { url = new URL(rawUrl); } catch (_) { return null; }
  // No embedded credentials or secrets in URL. TLS must terminate at the official service.
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      url.port || !url.hostname.includes('.') || url.pathname === '/') return null;
  return {url: url.href, token, revision};
}

function createOfficialEngineAdapter({env = process.env, fetchImpl = fetch,
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
  maxPolls = MAX_POLLS, clock = () => new Date()} = {}) {
  const config = officialEngineConfiguration(env);
  if (!config) return null;

  return async function generateOfficialCoupon({dayKey, preferences, now}) {
    if (typeof dayKey !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(dayKey) ||
        !(now instanceof Date) || !Number.isFinite(now.getTime())) {
      throw new Error('Invalid engine request');
    }

    // Privacy by design: DO NOT transmit subjectHash, clientId, phone token,
    // analyses, bets or other device identifiers to the generation service.
    const body = JSON.stringify({protocol: PROTOCOL, dayKey,
      generatedAfter: now.toISOString(), preferences});
    let response = await fetchImpl(config.url, {
      method: 'POST', redirect: 'error',
      headers: {Authorization: `Bearer ${config.token}`,
        'Content-Type': 'application/json', Accept: 'application/json'},
      body,
      signal: AbortSignal.timeout(20000),
    });
    // P18: generating the real Flutter coupon can take several minutes.
    // Never wait on a single long HTTP response; poll a job scoped to the
    // configured official host. No remote-provided polling URL is trusted.
    if (response?.status === 202) {
      const ticket = await readBoundedJson(response);
      if (ticket.protocol !== PROTOCOL || !JOB_ID.test(ticket.jobId || '')) {
        throw new Error('Invalid official engine ticket');
      }
      const pollUrl = new URL(`jobs/${ticket.jobId}`,
        new URL('.', config.url)).href;
      let finished = false;
      for (let attempt = 0; attempt < maxPolls; attempt++) {
        await sleep(POLL_INTERVAL_MS);
        response = await fetchImpl(pollUrl, {
          method: 'GET', redirect: 'error',
          headers: {Authorization: `Bearer ${config.token}`, Accept: 'application/json'},
          signal: AbortSignal.timeout(20000),
        });
        if (response?.status === 200) {finished = true; break;}
        if (response?.status !== 202) throw new Error('Official engine unavailable');
      }
      if (!finished) throw new Error('Official engine timeout');
    }
    if (!response || response.status !== 200) throw new Error('Official engine unavailable');
    // Stream-limited read avoids retaining arbitrary oversized provider results.
    const parsed = await readBoundedJson(response);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed) ||
        parsed.protocol !== PROTOCOL || parsed.officialEngine !== true ||
        parsed.revision !== config.revision ||
        !parsed.coupon || typeof parsed.coupon !== 'object') {
      throw new Error('Unverified official engine response');
    }
    // Independent server-side pre-match validation (the coordinator repeats it).
    // A generation may take several minutes: the original request clock
    // cannot certify that fixtures are still pre-match at completion.
    const checkedAt = clock();
    const validation = validateGeneratedCoupon({coupon: parsed.coupon, preferences, now:checkedAt});
    if (!validation.valid || validation.dayKey !== dayKey) {
      throw new Error('Invalid official coupon');
    }
    return parsed.coupon;
  };
}

async function readBoundedJson(response) {
  if (Number(response.headers?.get?.('content-length') ?? 0) > MAX_RESPONSE_BYTES) {
    throw new Error('Oversized engine response');
  }
  let raw = '';
  if (response.body && typeof response.body.getReader === 'function') {
    const reader = response.body.getReader();
    const chunks = []; let bytes = 0;
    try {
      while (true) {
        const {done, value} = await reader.read();
        if (done) break;
        const chunk = Buffer.from(value);
        bytes += chunk.length;
        if (bytes > MAX_RESPONSE_BYTES) throw new Error('Oversized engine response');
        chunks.push(chunk);
      }
    } finally {reader.releaseLock();}
    raw = Buffer.concat(chunks, bytes).toString('utf8');
  } else if (typeof response.text === 'function') {
    raw = await response.text();
    if (Buffer.byteLength(raw, 'utf8') > MAX_RESPONSE_BYTES) {
      throw new Error('Oversized engine response');
    }
  } else throw new Error('Engine response body unavailable');
  try {return JSON.parse(raw);} catch (_) {throw new Error('Invalid engine response');}
}

module.exports = {PROTOCOL, officialEngineConfiguration, createOfficialEngineAdapter,
  readBoundedJson};
