# Build 47 — Render / Neon on-demand deployment runbook (manual only)

> **Operational checklist, not a deployment.** No secret values, paid resources,
> feature-flag activation, Blueprint sync, or TestFlight release are performed
> by this document. Verify actual Render state before every operation.

## Verified in code and database (2026-11-13)

- GitHub source branch: `feature/b47-corrections`. Its B47 QA workflow
  previously passed backend, PostgreSQL integration, Flutter, and iOS compilation.
- Neon project `goalvdline-learning`, default branch `production`, database
  `neondb`: the additive `backend/learning/learning_schema.sql` migration
  has been applied. The `sb_on_demand_coupon_jobs_v1` queue exists.
- Existing Render services reported by the operator:
  `goalvdline-learning-api` (web, Free, Frankfurt), `smartbet-ai`
  (existing application web backend) and `smartbet-b45-flutter-staging`
  (private headless Flutter runner, Frankfurt). Their **current** deployment
  revisions, plans, private hostname, logs, and runtime settings must be
  rechecked directly in Render; none can be inferred from the GitHub repository.
- This B47 on-demand feature is different from B45's **daily**
  `background_worker.js`. Do **not** enable that daily worker or create its
  proposed separate paid service for an on-demand test.

## Deployment boundary and ordering

1. **Read-only inventory in Render.** Open existing learning API and Flutter
   runner services; check branch, commit, region, root directory, build/start
   commands, runtime environment key **names**, capacity, deployment logs, and
   the actual internal Flutter `hostport`. Never copy secret values into chat
   or GitHub. Confirm both services are in Frankfurt and private networking
   from the learning API is supported.
2. **Use staging first.** Prefer the already existing Neon
   `smartbet-b45-staging` branch for a controlled B47 integration test.
   Its database schema must be rechecked/extended before using it (production's
   migration did not automatically update another existing branch). Do not
   point staging testing at production data inadvertently.
3. **Align the official runner.** The private Flutter runner must execute the
   validated official engine version that supplies the complete B47 market
   and bookmaker contract, with a pinned **actual deployed** full Git SHA.
   Do not change `AUTO_COUPON_HEADLESS_REVISION` alone: both the checked-out
   code and the advertised revision must match. Re-test the private runner
   with authentication, durable journal, provider access, and real Flutter
   execution before enabling mobile requests.
4. **Prepare the existing learning API.** With Render's actual root directory
   as `backend`, the intended command is `node learning_only_server.js`.
   With repository root as working directory it is
   `node backend/learning_only_server.js`. Verify the build command installs
   `backend/package-lock.json` dependencies. Deploy a reviewed B47 commit
   to a safe staging target, not blindly over the live app.
5. **Configure but keep disabled until validated.** In Render Environment,
   verify values exist for `DATABASE_URL`, `LEARNING_SERVER_ENABLED`,
   `LEARNING_MOBILE_INGEST_ENABLED`, `LEARNING_ADMIN_TOKEN`,
   `LEARNING_SUBJECT_SALT`, and appropriate `LEARNING_PG_SSL`.
   The on-demand path additionally needs:
   `AUTO_COUPON_OFFICIAL_ENGINE_ENABLED`,
   `AUTO_COUPON_OFFICIAL_ENGINE_PRIVATE_RENDER_ENABLED`,
   `AUTO_COUPON_OFFICIAL_ENGINE_HOSTPORT`,
   `AUTO_COUPON_OFFICIAL_ENGINE_TOKEN`,
   `AUTO_COUPON_OFFICIAL_ENGINE_REVISION`,
   `ON_DEMAND_COUPON_REQUESTS_ENABLED`,
   `ON_DEMAND_COUPON_WORKER_ENABLED`,
   `ON_DEMAND_COUPON_WORKER_TOKEN`,
   `ON_DEMAND_COUPON_SERVER_POLL_ENABLED`, and optionally
   `ON_DEMAND_COUPON_POLL_INTERVAL_SECONDS` (30..300, default 60).
   Only set feature flags to `true` after the runner and database pass live
   checks. Do not place any mobile/admin/worker bearer token in Flutter.
6. **On-demand worker behavior.** The B47 scheduler is started inside
   `backend/learning_only_server.js` *only* with the explicit
   `ON_DEMAND_COUPON_SERVER_POLL_ENABLED=true` gate and complete engine
   configuration. The mobile job endpoint remains unavailable unless that
   processing loop started successfully. One database lease is acquired per
   job; stale instances cannot publish completed output.
7. **Verify, without invented data.** Check `/health/database` (only checks
   baseline learning tables), `/learning/v1/status`
   (`onDemandCouponRequestsEnabled` should be `true` **only** when the
   scheduler actually runs), authenticated POST
   `/learning/v1/mobile/on-demand-coupon/jobs`, GET job polling, and the
   official Flutter runner logs. Validate source-attributed bookmaker odds
   strictly **greater than** 1.20, three coordinated coupon variants,
   queued/running/ready state, privacy, server restart / lease reclaim, and
   no stale writes. Verify the Neon queue schema separately: the health probe
   does not check `sb_on_demand_coupon_jobs_v1`.
8. **No push / daily activation.** Leave APNs dispatch and B45 daily
   background-generation flags off. Do not trigger a TestFlight release
   until a real end-to-end B47 test has passed.

## Important Free-tier limitation (no added paid worker)

Render Free web services spin down after 15 minutes without inbound traffic.
A scheduler hosted inside a Free web service does **not** guarantee timely
completion of jobs after the iPhone closes or stops polling. Neon persists
queued jobs and permits safe recovery on a later wake-up, but it cannot keep
the Node process running. Do not claim the feature works reliably in the
background until an always-on *existing* service or an otherwise approved
execution arrangement has been tested. Explore reusing existing paid capacity
before proposing any additional fixed monthly spend.

## Source of truth

- `backend/learning_only_server.js` — opt-in on-demand server loop
- `backend/auto_coupon/on_demand_coupon_routes.js` — fail-closed mobile/worker routes
- `backend/auto_coupon/on_demand_coupon_service.js` — result validation and lease use
- `backend/auto_coupon/official_engine_client.js` — authenticated Flutter engine
- `backend/learning/learning_schema.sql` — additive Neon schema
- `deploy/p20_3d/render.p20_3d.staging.example.yaml` — **B45 daily**
  template, not an automatic B47 on-demand deployment
- Render free service behavior: https://render.com/docs/free
