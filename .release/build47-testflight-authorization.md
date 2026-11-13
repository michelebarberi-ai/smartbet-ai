# Build 47 — Authorized TestFlight Release

Version: `1.2.5+47`

Target: Apple TestFlight beta distribution only. This authorization does not publish the app to the App Store.

Source: `feature/b47-corrections`, code-matched to `release/b47-testflight` before the release-only workflow test gate.

Safety gate: `SmartBet iOS TestFlight` runs on this branch only for a push with the exact commit subject `release(build47): authorize TestFlight upload`.

Preflight: Flutter analyze plus focused remote coupon tests before certificates, archive and upload.

Scope: optional on-demand remote coupon requests, three coordinated coupons, persisted Neon recovery, and existing local coupon functionality.

This file is an audit marker for the user's explicit authorization of Build 47 TestFlight upload.
