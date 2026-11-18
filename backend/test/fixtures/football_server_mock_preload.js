'use strict';

// Loaded ONLY into the forked backend process by a local/CI integration test.
// No real network request can leave through global.fetch in this process.
// Never deploy this preload or import it from the application.
if (process.env.GOALVDLINE_LOCAL_STAGING_MOCK !== 'enabled') {
  throw new Error('Mock preload requires explicit local staging flag');
}

const providerHost = 'v3.football.api-sports.io';
let simulatedNow = Date.now();
let mode = 'healthy';
let upstreamCalls = 0;
let inFlight = 0;
let maximumInFlight = 0;
let releaseProbe = null;

Date.now = () => simulatedNow;

function signal(data) {
  if (process.send) process.send({from: 'football-mock', ...data});
}
function reply(requestId) {
  signal({
    type: 'ack',
    requestId,
    mode,
    upstreamCalls,
    maximumInFlight,
  });
}
process.on('message', msg => {
  if (!msg || typeof msg !== 'object') return;
  if (msg.command === 'mode' && ['healthy', 'limited', 'probe_hold'].includes(msg.value)) {
    mode = msg.value;
    reply(msg.requestId);
  } else if (msg.command === 'advance' &&
      Number.isSafeInteger(msg.ms) && msg.ms >= 0 && msg.ms <= 3600000) {
    simulatedNow += msg.ms;
    reply(msg.requestId);
  } else if (msg.command === 'release_probe') {
    if (releaseProbe) {
      releaseProbe();
      releaseProbe = null;
    }
    mode = 'healthy';
    reply(msg.requestId);
  } else if (msg.command === 'stats') {
    reply(msg.requestId);
  }
});

global.fetch = async (input, opts = {}) => {
  const url = new URL(String(input));
  if (url.protocol !== 'https:' || url.hostname !== providerHost ||
      opts?.headers?.['x-apisports-key'] !== 'LOCAL_ONLY_FAKE_KEY') {
    signal({type: 'blocked-external-fetch'});
    throw new Error('External network fetch blocked by isolated staging mock');
  }
  upstreamCalls++;
  inFlight++;
  maximumInFlight = Math.max(maximumInFlight, inFlight);
  signal({type: 'upstream', path: url.pathname, upstreamCalls});
  try {
    if (mode === 'limited') {
      return {
        ok: false, status: 429,
        text: async () => '{"errors":{"requests":"rate limit"}}',
      };
    }
    if (mode === 'probe_hold') {
      await new Promise(resolve => {releaseProbe = resolve;});
    } else {
      // Deliberately hold overlapping healthy requests so we can verify the
      // actual backend's queue and concurrency limit.
      await new Promise(resolve => setTimeout(resolve, 30));
    }
    return {
      ok: true, status: 200,
      text: async () => JSON.stringify({
        response: [{mock: true}],
        errors: {},
        results: 1,
      }),
    };
  } finally {
    inFlight--;
  }
};
