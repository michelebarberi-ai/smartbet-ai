# Build 64 — TestFlight upload authorization

The owner explicitly requested the most comprehensive feasible review of GoalVdLine followed by a new iPhone TestFlight build on 2026-11-17.

- Release branch: `release/b64-testflight`
- QA source SHA: `a5145df7ddaf834d3c9d27fe24a4149814e8864d`
- QA: full backend Node tests, Flutter static analysis, complete Flutter regression, targeted feature smoke checks: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/44092759300 (success).
- iOS build version: `1.2.5+64`, following successfully uploaded Build 63.
- Authorize a SINGLE TestFlight-only upload through existing GitHub Actions, gated by the exact release authorization commit message. The macOS job must pass all preflight tests, then archive/sign/export/upload with preexisting App Store Connect credentials.
- No new paid Render service, Neon migration, production admin mutation or public App Store release.
- See `docs/B64_TESTFLIGHT_RELEASE.md` for scope, diagnostic limitations and practical iPhone validation.
- The global odds data cannot confirm a specific Italian betting slip is available at a bookmaker's actual .it site; no such certification is claimed.
