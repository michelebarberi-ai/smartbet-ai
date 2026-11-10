'use strict';

// P20.3C: a process-local, sequential sweep loop. The authoritative per-user
// daily claim and lease remain in Neon via AutoCouponGenerationCoordinator.
// This loop is NOT an HTTP handler and does not use synthetic predictions.
const MIN_INTERVAL_MS = 30_000;
const MAX_INTERVAL_MS = 1_800_000;
const MAX_PAGES_PER_SWEEP = 50;
const CURSOR = /^[0-9a-f]{64}$/;

function createBackgroundScheduler({runBatch, intervalMs = 120_000,
  pageSize = 20, maxPagesPerSweep = 10,
  onError = () => {},
  setIntervalFn = setInterval, clearIntervalFn = clearInterval} = {}) {
  if (typeof runBatch !== 'function' || typeof onError !== 'function' ||
      !Number.isInteger(intervalMs) || intervalMs < MIN_INTERVAL_MS ||
      intervalMs > MAX_INTERVAL_MS || !Number.isInteger(pageSize) ||
      pageSize < 1 || pageSize > 25 ||
      !Number.isInteger(maxPagesPerSweep) || maxPagesPerSweep < 1 ||
      maxPagesPerSweep > MAX_PAGES_PER_SWEEP) {
    throw new Error('Invalid background scheduler settings');
  }
  let timer = null;
  let active = null;
  let stopped = false;
  let cursor = null;

  async function sweep() {
    if (stopped) return {status: 'stopped'};
    if (active) return {status: 'busy'};
    const work = (async () => {
      let checked = 0;
      let pages = 0;
      for (; pages < maxPagesPerSweep; pages++) {
        // On SIGTERM finish only the in-flight coordinator batch, not all
        // remaining pages; Neon owns safe recovery of interrupted jobs.
        if (stopped) return {status: 'stopped', checked, pages};
        const response = await runBatch({limit: pageSize, afterSubjectHash: cursor});
        if (response?.status !== 'checked' || !Number.isInteger(response.checked) ||
            response.checked < 0 || response.checked > pageSize ||
            (response.nextCursor !== null &&
             (typeof response.nextCursor !== 'string' || !CURSOR.test(response.nextCursor)))) {
          throw new Error('Invalid coordinator batch result');
        }
        checked += response.checked;
        // A short page is the end of this scan: start from the beginning on
        // the next interval, so new subscribers aren't forgotten.
        if (response.checked < pageSize || response.nextCursor === null) {
          cursor = null;
          return {status: 'completed', checked, pages: pages + 1};
        }
        // A malformed or repeated cursor must not cause a scan loop.
        if (cursor !== null && response.nextCursor <= cursor) {
          throw new Error('Coordinator cursor did not advance');
        }
        cursor = response.nextCursor;
      }
      // Bound each sweep. Resume the next page on the next interval to avoid
      // endlessly rescanning page one when there are many subscribers.
      return {status: 'partial', checked, pages};
    })();
    active = work;
    try {return await work;} finally {if (active === work) active = null;}
  }

  function start() {
    if (timer !== null || stopped) throw new Error('Scheduler already started or stopped');
    // Keep the background process alive. Do NOT unref this interval.
    timer = setIntervalFn(() => {void sweep().catch(() => {
      // No client data, subject hash, SQL text, credentials or provider
      // exceptions may enter background worker logs.
      try {onError('cycle_failed');} catch (_) { /* reporting only */ }
    });}, intervalMs);
    return sweep();
  }

  async function stop() {
    stopped = true;
    if (timer !== null) {clearIntervalFn(timer); timer = null;}
    if (active) {
      try {await active;} catch (_) { /* Neon lease expires if the host dies */ }
    }
  }
  return {sweep, start, stop};
}

module.exports = {createBackgroundScheduler, MIN_INTERVAL_MS, MAX_INTERVAL_MS};
