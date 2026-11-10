# B45 P20.3C — Dedicated asynchronous Render worker (staging only)

This is an independent Node.js **background process**, not a request handler.
It runs the existing `AutoCouponGenerationCoordinator` against the existing
Neon daily claims/leases (P20.3B). It calls the existing P18 official Flutter
engine adapter, which creates/polls jobs on the separate Flutter host (P20.3A).
No second forecasting model, invented predictions, notification dispatch or
new database queue is introduced.

## Deployment prerequisites — DO NOT enable in production yet

1. Apply/verify the **P20.3B schema migration on a staging Neon database**
   and ensure the database account can access the existing `sb_auto_coupon_*`
   tables. Verify concurrency and recovery with two separate staging processes.
2. Deploy a **separate official Flutter-capable runner** with a private
   persistent volume, HTTPS/authentication, correctly pinned Git revision,
   and the existing `AUTO_COUPON_HEADLESS_STATE_DIR` from P20.3A. A Node worker
   alone cannot execute Flutter. Do not point it at a local Mac or a dummy API.
3. Deploy a separate **Render Background Worker** service from this repository:
   **Start command:** `node backend/auto_coupon/background_worker.js`.
   This service has *no HTTP port*. Select a service tier capable of continuous
   execution, with enough resources/permissions for outbound Neon and HTTPS
   calls. Render's web service timeout no longer bounds the coordinator run.
4. Only on the background worker, and only after staging validation, supply
   the existing server-side values `DATABASE_URL`, `LEARNING_PG_SSL`,
   `AUTO_COUPON_OFFICIAL_ENGINE_URL`, `AUTO_COUPON_OFFICIAL_ENGINE_TOKEN`,
   `AUTO_COUPON_OFFICIAL_ENGINE_REVISION`, and set:
   - `AUTO_COUPON_BACKGROUND_ENABLED=true`
   - `AUTO_COUPON_WORKER_ENABLED=true`
   - `AUTO_COUPON_PREFERENCES_ENABLED=true`
   - `AUTO_COUPON_OFFICIAL_ENGINE_ENABLED=true`
   - Optional `AUTO_COUPON_BACKGROUND_INTERVAL_SECONDS=120` (30..1800)
   - Optional `AUTO_COUPON_BACKGROUND_PAGE_SIZE=20` (1..25)

All flags are OFF by default. **No automatic activation by a Git push**.
Do not set APNs/send flags until push transport has separate live validation.
The existing mobile/web feature status flags are *not* changed by this patch.
Use a separate Render worker service, not an HTTP endpoint, Cron web request,
or a `setInterval` attached to the learning web server.

## Safety and recovery

- Only opt-in subscribers are listed by the existing Neon repository.
- The coordinator checks each subscriber's **Europe/Rome** local schedule.
- Each actual generation claims the existing unique `(subject_hash,local_day)`
  record and renews its lease; a stale worker cannot publish `ready`.
- Errors fail closed. Interrupted work is reclaimed after the Neon lease
  expires, at most five attempts. Runner journals on a persistent volume
  recover completed official output if still pre-match valid.
- Scans are sequential, bounded by 20 subscribers per page and 10 pages per
  pass by default. They resume from the last cursor on the next pass; a full
  sweep starts again at the beginning. No overlapping sweeps in one process.
- Worker retries occur on the next scheduled sweep, but a restart during a
  Flutter run can cause an additional engine call; only one `ready` result per
  user/day can be published (not exactly-once provider execution).
- Stop (`SIGTERM`/`SIGINT`) prevents new sweeps and allows the current sweep
  to finish if the platform shutdown deadline permits. Otherwise Neon leasing
  handles recovery after the timeout.
- No APNs are sent, and no client IDs, betting amounts, tokens or predictions
  are logged by this worker entry point.

## Tests (no Neon/Flutter calls)

```
node --test backend/test/auto_coupon_background_scheduler.test.js
node --test backend/test/auto_coupon_*.test.js \
  backend/test/learning_mobile_auth.test.js \
  backend/test/learning_retrospective.test.js \
  backend/test/learning_routes.test.js
```

## Live checks still required

Staging Neon migration, separate live process restart/failover, cancellation
while processing, expiry/reclaim after provider outage, deployment/health
monitoring, and APNs delivery remain **unverified**. The background worker
requires an active Render Background Worker service; source code alone does
not run by itself or guarantee a daily generation when provider data is scarce.
