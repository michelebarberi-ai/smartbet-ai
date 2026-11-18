'use strict';

// A process-local safety valve for ALL API-Football paths, not per-URL.
// It prevents a provider 429 from becoming a flood of 429 on different
// fixture/odds/stats paths. It NEVER retries and NEVER treats stale data
// as fresh. Cached responses and same-key single-flight stay in server.js.
function createFootballProviderGate({
  now = () => Date.now(),
  maxConcurrent = 4,
  baseCooldownMs = 2 * 60 * 1000,
  maxCooldownMs = 30 * 60 * 1000,
} = {}) {
  if (!Number.isSafeInteger(maxConcurrent) || maxConcurrent < 1 ||
      maxConcurrent > 100 ||
      !Number.isSafeInteger(baseCooldownMs) || baseCooldownMs < 1000 ||
      !Number.isSafeInteger(maxCooldownMs) || maxCooldownMs < baseCooldownMs) {
    throw new TypeError('Invalid football provider gate configuration');
  }

  let active = 0;
  let blockedUntil = 0;
  let consecutiveRateLimits = 0;
  let needsProbe = false;
  let probeInFlight = false;

  function localError(code, seconds) {
    const error = new Error('Il fornitore sportivo non è al momento disponibile.');
    error.code = code;
    error.statusCode = 503;
    error.upstreamStatus = null;
    error.retryAfterSeconds = Math.max(1, Math.ceil(seconds));
    return error;
  }

  async function run(task) {
    if (typeof task !== 'function') throw new TypeError('Expected task function');

    const timestamp = now();
    if (timestamp < blockedUntil) {
      throw localError('FOOTBALL_PROVIDER_COOLDOWN',
        (blockedUntil - timestamp) / 1000);
    }
    // Only a single probe can resume service after a rate-limit event.
    // Remaining requests immediately fail locally; they never go upstream.
    if (needsProbe && probeInFlight) {
      throw localError('FOOTBALL_PROVIDER_COOLDOWN', 2);
    }
    if (active >= maxConcurrent) {
      throw localError('FOOTBALL_PROVIDER_BUSY', 1);
    }

    const probing = needsProbe;
    if (probing) probeInFlight = true;
    active++;
    try {
      const result = await task();
      if (probing) {
        needsProbe = false;
        blockedUntil = 0;
        consecutiveRateLimits = 0;
      }
      return result;
    } catch (error) {
      if (error?.code === 'FOOTBALL_PROVIDER_RATE_LIMIT') {
        // In-flight requests may have been launched before the first 429.
        // Each additional 429 increases the guard time, bounded to 30m.
        consecutiveRateLimits = Math.min(consecutiveRateLimits + 1, 12);
        const delay = Math.min(maxCooldownMs,
          baseCooldownMs * (2 ** (consecutiveRateLimits - 1)));
        blockedUntil = Math.max(blockedUntil, now() + delay);
        needsProbe = true;
      } else if (probing) {
        // An inconclusive probe must not release a stampede. Try one again
        // after the base delay. Only a good response confirms recovery.
        blockedUntil = now() + baseCooldownMs;
      }
      throw error;
    } finally {
      active = Math.max(0, active - 1);
      if (probing) probeInFlight = false;
    }
  }

  return {run};
}

module.exports = {createFootballProviderGate};
