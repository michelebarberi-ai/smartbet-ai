# GoalVdLine iOS 1.2.5 (Build 64) — TestFlight QA and release

## Source and release gate
- Source: feature/b64-sports-reading, based on the successfully uploaded Build 63.
- Build: `1.2.5+64`. The intended branch is `release/b64-testflight`.
- GitHub Actions upload requires exactly one authorization commit with the message `release(build64): authorize TestFlight upload`; creation of the release branch alone must not upload.
- The macOS job repeats backend syntax, full Node backend tests, Flutter static analysis, all Flutter tests and iOS archive/signing/export. If a gate fails, no TestFlight upload should be claimed.
- Uses existing GitHub signing credentials and App Store Connect. No paid Render/Neon provisioning, no database migration, no App Store public release.

## B64 changes to verify
1. Combinazioni UI: redundant Multimercato Ranking switch removed; Ranking's diagnostic data quality, simulations and prospective league/market history visible as an expandable read-only detail for results. Does not change generated picks.
2. Combinazioni: a single “Combo avanzate” control, with **Con quote** (real quoted combo candidates) and **Solo simulazione** (unquoted Poisson market combinations). Simulated options must never appear as verified coupons.
3. League filters: each competition shows how many future fixture candidates have valid IDs in the chosen period; a live total of the selected fixture candidates appears above **Applica** and in Combinazioni after applying. These are NOT the number of reliable predictions, and catalog-only competitions can have zero.
4. Odds and schedule: when Palinsesto Italia is active, filter the global odds feed to brands present in Italy, with an independent eligible-competition filter; maintain isolated cache keys for filtered vs global quotes, reject unquoted/out-of-threshold picks. IMPORTANT: the global source cannot certify a specific fixture/market is published on the bookmaker's actual Italian .it schedule. UI explicitly discloses this and users must verify it.
5. Only finalized/audited selections are presented as complete in automatic coupons and Combinazioni, with updated counters and forecasts below selected probability threshold kept out of the main preview.
6. Improved non-mechanical sporting market relation text; Home's AI panel is called “Analisi motori AI”.
7. Home: remove redundant “Partite da analizzare oggi” large card (top AiCard already shows count, MenuGrid still offers Crea Schedina/Analisi Partite); move “Qualità e apprendimento” and internal learning controls below “I tuoi strumenti”.

## Verify manually in TestFlight
- Check Home: no daily card; greeting, online status and daily count remain; MenuGrid works; learning summary at bottom with unchanged stats.
- Combinazioni: periods / selected league count / favorites / up to 3 markets / one advanced combo selector, both modes, ranking details, X Premium, Auditor, absent quotes, invalid countries and minimum probability.
- Schedina AI: manual and automatic modes, three variants, real bookmaker labels, >1.20 thresholds, high handicap alternative, club availability with “Palinsesto Italia” switched on and off.
- Diego AI: some matches can remain N/D when upstream real history is inadequate; do not invent results. Check detailed reasons and status of Auditor.
- Server-generated coupons and notification when app closed/background: device-specific APNs not certified by static tests.
- Admin setup and emails/TOTP: test from iPhone without sharing codes or passwords; depends on existing Render/Resend configuration.

## Known limitations
- Source-based brand filter is NOT a verification of an actual .it bookmaker palinsesto; completing this feature requires a compatible country-specific source.
- Catalog fixtures are not all necessarily analyzable or playable. Serie D fixture coverage is limited by provider.
- Incomplete Diego coverage and iOS background push/remote worker availability require live device and backend validation.
- Flutter/Node suites validate deterministic paths, not an end-to-end simulation on a real iPhone or guaranteed future prediction accuracy.
