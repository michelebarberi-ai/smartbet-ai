# Build 66 — Three-engine central learning: safe opt-in rollout

## Existing infrastructure (read-only verification, 18 Nov 2026)

- Neon project: `goalvdline-learning`.
- Existing production branch: `production` (unchanged).
- Existing staging branch: `smartbet-b45-staging` (expires 2026-11-30).
- `sb_learning_predictions_v1` exists and currently accepts ONLY `smartBet` and `diego`.
- No database writes, DDL, purchases, Render deploys, or TestFlight uploads were executed by this change.

## Implemented on the feature branch

1. Third-engine *original* pre-kickoff probability snapshots are saved locally
   for seven supported full-time markets: 1, X, 2, GOAL, NO GOAL,
   OVER 2.5 and UNDER 2.5. The model remains uncalibrated SHADOW.
2. The existing local outbox collects these seven snapshots in one durable
   operation only after explicit opt-in, never retroactively.
3. Provenance indicates if the simulator reused SmartBet or Diego expected goals.
   **Shared xG must not be treated as independent confirmation.**
4. A mobile-upload request remains manually confirmed by the user, with
   scoped Bearer credential (not admin token), HTTPS, no redirects, maximum
   20 predictions/5 fixtures and idempotent server acknowledgement.
5. The server continues verifying the fixture and kickoff via the sports
   provider. It, not the device, resolves settled results.
6. The dedicated simulator gate is OFF by default. Missing capability leaves
   simulator drafts on the device, without blocking old-engine uploads.

## Manual deployment sequence — NOT authorized by this code change

1. Review `backend/learning/migrations/b66_simulator_ingest.sql`.
   It adds `simulator_input_source` and replaces the engine CHECK constraint.
   Apply on staging **only with explicit approval**. Confirm the old
   `smartBet` and `diego` records and constraints remain intact.
2. In staging, deploy the backend code on existing infrastructure with
   `LEARNING_SIMULATOR_SCHEMA_READY=false` and
   `LEARNING_SIMULATOR_INGEST_ENABLED=false`. Do not enable new paid services.
3. Run server and Flutter tests plus an authenticated staging smoke test
   before deciding whether to migrate production.
4. Obtain a **separate explicit approval** before modifying production
   Neon or enabling the two feature flags in production.
5. Only after migration and review may the two flags be explicitly
   switched to `true` in the existing Render service configuration.
   The status endpoint then reports `simulatorIngestEnabled=true`.
6. Even after enablement, *user consent and manual upload confirmation*
   remain necessary. This change does not schedule background transfers.
7. Revocation, remote erase, TTL, deduplication and existing security remain
   on the established API path.

## Security/integrity notes

- No new user identity, email, phone, IP address, raw device identifier,
  betting odd, score claimed by the client, or admin credential is sent.
- Existing submissions with `smartBet` and `diego` retain their SQL path.
- For `simulator`, the server only accepts seven supported markets and
  `inputSource` set to `smartBet` or `diego`. Missing or extra data is rejected.
- Existing rows remain untouched by the proposed migration. The DB's
  UNIQUE(subject_hash, fixture_id, engine, market) stays in place.
- If a manual DB migration has not happened, leave the server gates OFF.
- Neither a high MEI nor paired Brier results promotes an engine into live picks.
- Central league-by-league MEI will require verified competition metadata
  collected server-side; this change does not invent that mapping.

## Quality verification

- Node tests: `npm --prefix backend test`
- Flutter: `flutter analyze --no-pub --no-fatal-infos`
- Flutter tests: `flutter test --no-pub --reporter compact`
- CI workflow: `.github/workflows/b66-three-engine-sync-qa.yml`.
- Feature branch: `feature/b66-three-engine-neon-sync`; not a release branch.
