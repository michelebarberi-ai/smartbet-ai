# GoalVdLine iOS 1.2.5 (Build 59) — TestFlight

Release authorized by the owner to publish an iPhone test build via GitHub Actions.

## New in B59
- Clearer partial results and excluded-candidate diagnostics in Combinazioni / Schedina.
- Diversified preliminary searches across competitions in X Premium / Multimercato; no artificial xG or playing odds.
- B53 minute-by-minute goal replay and B54 prospective comparison stay SHADOW; do not change official probabilities.
- Diego AI odds outage no longer erases its sporting forecast; removed Sisal-only request and misleading labels.
- QuoteLab historical odds-versus-results analysis is information-only, based on saved prospective picks.
- Public Home displays simplified AI learning report; technical Brier/SHADOW reports separated.
- Owner login entry under Settings: password + 6-digit Authenticator code and optional 8-digit email recovery.
- Public users retain their data consent and remote-erasure controls.
- Local result resolution automatically triggers when app returns foreground, 30-min throttling; pull-to-refresh remains manual.

## Security/release limitations
- **B58/B59 owner authentication is disabled on the live server until production-safe shared session/OTP storage, admin authorization, explicit password and TOTP provisioning and verified recovery email have been configured.** The login UI is visible but not yet operational. NO administrator credentials embedded in Flutter.
- The public build uses GOALVDLINE_INTERNAL_DIAGNOSTICS=false by default, so technical cards are hidden unless authenticated owner panels are opened.
- Telegram/web external consensus is only a local calculation service: NO mass-scraping, no remote ingestion, no automatic web training.
- The old server administrator API token remains server-only, unchanged and inaccessible to Flutter.
- No new paid services, Neon migration, SMS provider or mail provider activated.
- Never promote SHADOW calibration or retroactive historical data as prospective or verified without a matching timestamp.
- The TestFlight upload is NOT App Store public release or YouTube upload.

## QA
- B59 GitHub Actions (Flutter analyze, full Flutter suite, full Node backend suite): https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/43776918477
- iOS release workflow blocks upload before provisioning if Flutter analyze or B59 targeted tests fail; Apple upload requires existing GitHub signing secrets.
