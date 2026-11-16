# GoalVdLine iPhone Build 61 — Owner first activation (TestFlight)

Owner-approved release of GoalVdLine 1.2.5+61, based on the B60 release,
adding secure first-time owner enrollment to the existing password + Authenticator login.

## Availability and privacy
- The server's production owner setup readiness was verified on
  2026-11-16 through GitHub Actions, with ready=true, activated=false,
  and the existing learning /health still returning HTTP 200.
- The account is NOT created or activated by installing this build.
- The owner must explicitly request an 8-digit code sent ONLY to the
  fixed server-verified email address, enter that code in the app,
  pair a TOTP authenticator using a manual 32-character secret,
  and create a password of at least 16 characters.
- No admin password, QR seed, provider API key or service admin token
  is embedded in GitHub, the Flutter bundle or TestFlight metadata.
- The owner login session grants only the limited
  `owner-staging-login-only` scope; it does NOT make the legacy
  learning admin API public or bypass admin authorization.

## Test requirements
- Previously passed B61 full Flutter regression and Node/PostgreSQL
  suite: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/43822469223
- Production read-only readiness:
  https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/43938782137
- This release workflow repeats owner onboarding/UI tests and Flutter
  analysis on macOS before signing/archive/upload.
- Resend live delivery itself has not yet been confirmed. If the owner
  code fails to send, the UI will explain the failure; do not
  bypass server verification with a hardcoded password.

## Other features
- Preserves B60 Diego historical data improvements (youth/national
  competitions, short negative cache, transparent unavailable reasons),
  quote-blind sports AI and existing coupon behavior.
- No Neon migrations, new paid plans, or new data transmission are
  triggered by this iPhone release.
