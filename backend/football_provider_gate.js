'use strict';

// Per-process provider safety valve shared by all paths. No retries and no
// stale-data promotion. Cache and same-key single-flight remain upstream in
// server.js. A bounded wait queue prevents normal short spikes from causing
// hundreds of local 503s when the provider is healthy.
function createFootballProviderGate({
  now = () => Date.now(),
  maxConcurrent = 4,
  maxQueue = 0, // explicit opt-in, preserving legacy tests/callers
  maxWaitMs = 8000,
  baseCooldownMs = 2 * 60 * 1000,
  maxCooldownMs = 30 * 60 * 1000,
} = {}) {
  if (!Number.isSafeInteger(maxConcurrent) || maxConcurrent < 1 ||
      maxConcurrent > 100 ||
      !Number.isSafeInteger(maxQueue) || maxQueue < 0 || maxQueue > 500 ||
      !Number.isSafeInteger(maxWaitMs) || maxWaitMs < 1000 ||
      maxWaitMs > 60000 ||
      !Number.isSafeInteger(baseCooldownMs) || baseCooldownMs < 1000 ||
      !Number.isSafeInteger(maxCooldownMs) || maxCooldownMs < baseCooldownMs) {
    throw new TypeError('Invalid football provider gate configuration');
  }

  let active = 0;
  const pending = [];
  let blockedUntil = 0;
  let consecutiveRateLimits = 0;
  let rateLimitEpoch = 0;
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

  function rejectPending(error) {
    for (const ticket of pending.splice(0)) {
      clearTimeout(ticket.timer);
      ticket.reject(error);
    }
  }

  function releaseOneQueued() {
    if (pending.length === 0 || active >= maxConcurrent) return;
    const current = now();
    if (current < blockedUntil || needsProbe) {
      rejectPending(localError('FOOTBALL_PROVIDER_COOLDOWN',
        Math.max(1, (blockedUntil - current) / 1000)));
      return;
    }
    // Reserve before waking to prevent a newly arriving request from
    // stealing the slot; FIFO fairness with no busy-spin.
    const ticket = pending.shift();
    clearTimeout(ticket.timer);
    active++;
    ticket.resolve();
  }

  async function acquire() {
    const timestamp = now();
    if (timestamp < blockedUntil) {
      throw localError('FOOTBALL_PROVIDER_COOLDOWN',
        (blockedUntil - timestamp) / 1000);
    }
    if (needsProbe && (probeInFlight || active >= maxConcurrent)) {
      throw localError('FOOTBALL_PROVIDER_COOLDOWN', 2);
    }

    if (active < maxConcurrent && pending.length === 0) {
      active++;
      return;
    }
    if (needsProbe || maxQueue === 0 || pending.length >= maxQueue) {
      throw localError('FOOTBALL_PROVIDER_BUSY', 1);
    }
    await new Promise((resolve, reject) => {
      const ticket = {resolve, reject, timer: null};
      ticket.timer = setTimeout(() => {
        const index = pending.indexOf(ticket);
        if (index === -1) return;
        pending.splice(index, 1);
        reject(localError('FOOTBALL_PROVIDER_BUSY', 1));
      }, maxWaitMs);
      pending.push(ticket);
    });
    // A ticket wakes up only when a slot is pre-reserved.
  }

  async function run(task) {
    if (typeof task !== 'function') throw new TypeError('Expected task function');
    await acquire();

    const t = now();
    if (t < blockedUntil || (needsProbe && probeInFlight)) {
      active--;
      releaseOneQueued();
      throw localError('FOOTBALL_PROVIDER_COOLDOWN',
        Math.max(1, (blockedUntil - t) / 1000));
    }

    const probing = needsProbe;
    const startRateLimitEpoch = rateLimitEpoch;
    if (probing) probeInFlight = true;
    try {
      const result = await task();
      if (probing && startRateLimitEpoch === rateLimitEpoch) {
        needsProbe = false;
        blockedUntil = 0;
        consecutiveRateLimits = 0;
      }
      return result;
    } catch (error) {
      if (error?.code === 'FOOTBALL_PROVIDER_RATE_LIMIT') {
        rateLimitEpoch++;
        // Several already-in-flight requests may return 429 together.
        // Escalation is bounded; only the first recovery probe releases
        // the circuit, not an old successful call.
        consecutiveRateLimits = Math.min(consecutiveRateLimits + 1, 12);
        const delay = Math.min(maxCooldownMs,
          baseCooldownMs * (2 ** (consecutiveRateLimits - 1)));
        blockedUntil = Math.max(blockedUntil, now() + delay);
        needsProbe = true;
        rejectPending(localError('FOOTBALL_PROVIDER_COOLDOWN',
          (blockedUntil - now()) / 1000));
      } else if (probing) {
        blockedUntil = Math.max(blockedUntil, now() + baseCooldownMs);
        rejectPending(localError('FOOTBALL_PROVIDER_COOLDOWN',
          (blockedUntil - now()) / 1000));
      }
      throw error;
    } finally {
      active = Math.max(0, active - 1);
      if (probing) probeInFlight = false;
      releaseOneQueued();
    }
  }

  return {run};
}

module.exports = {createFootballProviderGate};
