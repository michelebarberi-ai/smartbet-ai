# Build 66 — Three-engine central learning: safe opt-in rollout

## Existing infrastructure (read-only verification, 18 Nov 2026)

- Neon project: `goalvdline-learning`.
- Existing production branch: `production` (unchanged).
- Existing staging branch: `smartbet-b45-staging` (expires 2026-11-30).
- `sb_learning_predictions_v1` exists and currently accepts ONLY `smartBet` and `diego`.
- **Staging migration applied 18 Nov 2026** to the existing branch `smartbet-b45-staging` only.
- Verified `simulator_input_source`, engine CHECK (smartBet/diego/simulator),
  provenance CHECK and original uniqueness constraint.
- The staging table had 0 rows before and after. A temporary-table transaction
  accepted the two original engines and simulator with valid xG sources, while
  rejecting simulator records with missing/invalid source and legacy records
  with an unexpected source. No permanent prediction rows were added.
- Production schema remains unchanged (only SmartBet/Diego). No purchase, Render
  deploy, or TestFlight upload was executed.

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

1. **Done, staging only.** Reviewed and applied
   `backend/learning/migrations/b66_simulator_ingest.sql` on
   `smartbet-b45-staging`; constraints and compatibility were checked.
   The existing staging branch expires 2026-11-30.
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

## GitHub-only TestFlight release preparation

- `.github/workflows/ios-testflight.yml` now recognizes only
  `release/b66-testflight` with an exact push commit message
  `release(build66): authorize TestFlight upload`.
- The Build 66 release must pin `version: 1.2.5+66` in `pubspec.yaml`.
- The backend and full Flutter regressions run before iOS signing/upload.
- The B66 feature branch is not a TestFlight trigger. No release branch has
  been created by this preparation step.
- Node release contract regression in
  `backend/test/b66_release_workflow_contract.test.js` guards this behavior.
- Publishing remains GitHub-only; do not manually use a Mac or Codemagic.

## Quality verification

- Node tests: `npm --prefix backend test`
- Flutter: `flutter analyze --no-pub --no-fatal-infos`
- Flutter tests: `flutter test --no-pub --reporter compact`
- CI workflow: `.github/workflows/b66-three-engine-sync-qa.yml`.
- Feature branch: `feature/b66-three-engine-neon-sync`; not a release branch.
