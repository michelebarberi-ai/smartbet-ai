# GoalVdLine Build 45 / P18 — Real official Flutter engine (experimental)

This stage addresses the P17 proof that genuine SmartBetAutoCouponService takes
about 2m40s and cannot fit in P15's 20-second synchronous HTTP timeout.
It does NOT port SmartBet AI into a second, independent Node forecasting model.

## What is implemented

- `test/engine/goalvdline_official_headless_worker_test.dart` runs the **same**
  official `SmartBetAutoCouponService`, loading preferences supplied by the
  runner, and exports *only* the validated `GoalVdLineOfficialCouponContract`.
- `official_headless_runner.js` is a standalone, opt-in Node HTTP job host on
  **127.0.0.1**, on a machine with Flutter installed. It launches the headless
  engine as a subprocess, returns HTTP 202 plus a random job ID, and makes the
  finished, validated result available at `GET /coupon/jobs/:jobId`.
- `official_engine_client.js` polls a pinned **HTTPS** engine host for at most
  100 × 5s and never follows a URL contained in an untrusted response. The
  returned revision must match the configured source revision. The existing
  200-response path is unchanged.
- Input has no user/client ID, mobile token, phone history or bet placement.
  No odds/probabilities are generated or fabricated by Node.
- Each runner accepts **one live job at a time**; no parallel Flutter jobs.
  Tokens are checked before any work and the runner is OFF by default.

## Fast tests (no network, no push)

```sh
node --test backend/test/auto_coupon_official_headless_runner.test.js \
  backend/test/auto_coupon_official_engine_client.test.js
flutter test --reporter compact test/engine/goalvdline_official_headless_worker_test.dart
```

The Flutter test is skipped by default. Its real execution must be launched
with a properly authenticated request and isolated output path by the runner.

## Hosting and safety

The standalone host requires these **server-side** variables:

- `AUTO_COUPON_HEADLESS_HOST_ENABLED=true`
- `AUTO_COUPON_HEADLESS_TOKEN` — independent random secret of 32+ chars
- `AUTO_COUPON_HEADLESS_REVISION` — verified, pinned Git SHA
- `AUTO_COUPON_HEADLESS_PORT` — optional (8799 default)

It binds only to loopback. A separately configured TLS reverse proxy/network
path is needed before the Render service can reach it; never expose its
unauthenticated port publicly. The original service has different gates
(`AUTO_COUPON_OFFICIAL_ENGINE_*`); they remain OFF until an actual deployment
is ready. NEVER put these tokens in the Flutter app or Git.

**Not production-ready:** the experimental host keeps job state in memory;
restarts discard pending jobs. The dedicated Render learning server's current
`/worker/run` request may still exceed its inbound HTTP timeout if it waits for
multi-minute remote execution. Before enabling schedules for users, implement
persistent job orchestration, idempotent retries/recovery and an appropriate
separate Flutter-enabled runner, configure and test a scheduler and APNs
against signed iOS builds, and verify golden parity and resource limits.

Do NOT enable `AUTO_COUPON_WORKER_ENABLED` or APNs gates as a result of this patch.
