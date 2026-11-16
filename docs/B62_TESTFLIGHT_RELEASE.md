# GoalVdLine iOS 1.2.5 (Build 62) — TestFlight release

## Release source
- Branch: `release/b62-testflight`; built on the B61 TestFlight source and the successfully tested `fix/b62-owner-coldstart-readiness` change set.
- Authorize **one** TestFlight upload only with commit message `release(build62): authorize TestFlight upload`.
- The GitHub iOS workflow must run static analysis AND full Flutter regression before preparing App Store Connect credentials, archiving, signing and uploading.
- Version: `1.2.5+62`. No new fixed-cost infrastructure or manual Mac/Codemagic steps.

## Changes included
1. **Owner activation stability**: longer network timeouts for initial Render Free wake-up, safe GET retry/status check from the iPhone, no automatic repeated owner email requests, and explicit feedback when sending status is uncertain. Existing password and Authenticator TOTP security preserved.
2. **High handicap alternatives**: for handicap of magnitude >=3, show a *separate informational* quoted option in Crea Schedina AI and Combinazioni AI. Only offer it when the independent sports estimate is at least 65% (or user's higher threshold), real bookmaking odd >1.20, named bookmaker and local Auditor pass. Do **not** silently replace the original coupon pick. State clearly when none is available.
3. **Daily learning odd gate**: align Risultati del giorno with the shared playable-quote rule strictly >1.20, allowing valid 1.21–1.24 quotes. Adaptive corrections are still opt-in and subject to prospective safety gates; live central model promotions remain disabled.
4. **League/market reliability ranking**: add a read-only, market-filterable, conservatively ordered ranking to Intelligenza e apprendimento. Requires >=50 prospective resolved predictions on >=14 distinct match days per league/market; sort by Wilson 95% lower bound; do not imply guaranteed future win rates. Uses **local iPhone history** and no paid central API.
5. Preserve B60 historical coverage improvement and Diego AI N/D reasons, 3-coupon UI, combinations market support, odds/audit protections, and owner MFA onboarding from Build 61.

## Known constraints / to verify on iPhone
- Diego AI predictions depend on the genuine sports data supplied by upstream providers; absence of enough reliable data still leads to an explicit N/D, not a synthetic prediction.
- Serie D is allowed by the existing filter when matches are delivered, but **availability of all groups/matches is not certified**.
- Local notifications for a coupon completed in the foreground exist; **server-to-iPhone push for completed remote jobs when app is closed is not confirmed active** in production.
- This release adds a **historical local ranking**, not automatic centralized league-weighted learning in live coupons.
- Resend accepted the last owner activation email delivery test after server address-case normalization; full activation/password/TOTP login still requires real iPhone verification. Never copy an OTP, password or authenticator seed into tickets or logs.
- This is a TestFlight test release, NOT a public App Store release.

## Verification
- Branch full Flutter analyze + regression suite passed:
  https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/43952935526
- B61 staged owner functionality:
  https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/43939017119
- Build 62 workflow re-runs full Flutter regression on macOS, checks the exact version, then signs/uploads with existing GitHub App Store Connect secrets.

## User acceptance on iPhone
- First activation: email code -> pair TOTP -> set >=16-character password -> password+TOTP login.
- Render wake-up from inactive state, retry status check without duplicate OTP.
- Elevated HCP +3/-3 alternatives shown only if real bookmaker quote passes; never change coupon automatically.
- Combinazioni: same test for elevated HCP; verify number of proposed games and three coupon visual consistency.
- Intelligenza e apprendimento: correct treatment of insufficient samples, filters by market, ranked historic uncertainty.
- Diego AI, Serie D feed coverage, remote coupon completion and lock-screen notification behavior (report unresolved issues).
