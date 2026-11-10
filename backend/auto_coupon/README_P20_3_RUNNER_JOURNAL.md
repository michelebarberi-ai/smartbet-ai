# Build 45 / P20.3A — Headless runner journal (staging only)

This incremental patch makes the *separate*, Flutter-equipped P18 job host
more restart-aware. It does **not** deploy or activate scheduled generation,
Neon job leasing, APNs, or a new forecasting engine.

## New optional durability setting

The headless host may be configured with the SERVER-ONLY setting:

`AUTO_COUPON_HEADLESS_STATE_DIR=/absolute/path/on/a/persistent/volume`

- The directory must reside on a **persistent volume attached to the separate
  Flutter host**. The ephemeral filesystem of a Render web service is not a
  safe substitute. Do not place the directory in the Flutter app or Git.
- One headless host process only. This journal is **not** a distributed lock or
  an HA queue. For multi-instance orchestration use Neon leases/transactions.
- Without this optional setting, the original P18 in-memory behavior remains.
- Jobs are atomic-written to private JSON files. No bearer token, APNs token,
  client identifier, user prediction history, or sportsbook credentials are
  written; request preferences and validated result payloads *are* stored.
  Treat the volume as private and access-controlled.
- On restart: completed valid jobs can still be fetched using their original
  ticket; interrupted `running` jobs are marked failed, **not** fabricated as
  completed. A new authenticated request may start a new job.
- POST idempotency groups matching revision + Rome day + preferences, ignoring
  the short-lived `generatedAfter` timestamp. A failed job may be retried.
- Every GET of a `ready` job re-checks the current kickoff times and pinned
  revision. A match that has already started is never served as pre-match.
- Concurrent HTTP requests cannot start two Flutter subprocesses in one host.
- The coordinating worker and bridge also re-check pre-match eligibility
  after a slow engine response, rather than reusing the original request time.
- Triple mode requires a genuine finite quoted odd >= 1.25 for each event;
  SINGLE mode keeps its backward-compatible odds contract.

## Tests (no network)

```sh
node --test \
  backend/test/auto_coupon_durable_headless_runner.test.js \
  backend/test/auto_coupon_official_headless_runner.test.js \
  backend/test/auto_coupon_official_engine_client.test.js \
  backend/test/auto_coupon_generation_coordinator.test.js \
  backend/test/auto_coupon_three_variants.test.js
```

Run the normal backend and Flutter suites as well. No configuration flag should
be enabled in production as a consequence of these tests.

## Still required for P20.3B / production

The repository implementing `claimAutoCouponRun`, `finishAutoCouponRun`,
`listAutoCouponSubscribers`, and its SQL migrations were **not included** in
this source bundle. The current dedicated Render `/worker/run` route still
waits synchronously for slow Flutter generation; this can exceed the HTTP
request timeout and cannot guarantee recovery after a process crash. To finish:

1. Introduce durable Neon `queued/running/ready/retry` leases with fencing
   tokens, expiry, attempt limits, `UNIQUE(subject_hash, day_key)` and atomic
   compare-and-set completion; do not reissue an unsafe expired lease.
2. Make the Render entry point acknowledge quickly; a separate scheduled
   worker should claim and finish jobs outside its inbound HTTP request.
3. Verify retry after restart, concurrent worker claims, worker timeouts,
   invalidated preferences, day rollover, and provider outages.
4. Deploy a separate always-on Flutter-enabled runner with TLS/private ingress,
   pinned source revision and restricted secret management.
5. Only then plan scheduling and signed-device APNs tests. Keep all flags OFF.
