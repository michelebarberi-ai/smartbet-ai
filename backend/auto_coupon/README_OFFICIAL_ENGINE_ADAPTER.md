# GoalVdLine Build 45 / P15 — Official engine bridge (disabled by default)

The existing AutoCoupon scheduler, database claims and APNs dispatch **cannot
produce genuine coupons** until an official engine is deployed separately.
This module is only a secure HTTP transport to that engine, not a replacement
for the app's `SmartBetAutoCouponService` / `SmartBetCouponService`.

## Server-only configuration

- `AUTO_COUPON_OFFICIAL_ENGINE_ENABLED=true` (OFF by default)
- `AUTO_COUPON_OFFICIAL_ENGINE_URL=https://<your-engine-host>/coupon/generate`
- `AUTO_COUPON_OFFICIAL_ENGINE_TOKEN=<distinct secret 32+ chars>`
- `AUTO_COUPON_OFFICIAL_ENGINE_REVISION=<git SHA of verified official engine>`

This is **in addition to**, and not a replacement for, the worker's existing
feature gates, database configuration and worker token. Never embed server
secrets in Flutter or commit them to Git. Do not enable these flags until a
separately hosted implementation of the **same official Flutter engine** has
been ported and checked against reference outputs.

## Request contract

`POST` with `Authorization: Bearer <server token>` and JSON:

```
{"protocol":"goalvdline-official-coupon-v1","dayKey":"2026-11-09",
 "generatedAfter":"2026-11-09T08:15:00.000Z",
 "preferences":{"requested":true,"hour":8,"minute":0,"events":3,
   "minimumMarketProbability":65,"market":"MULTI","notifyChanges":true}}
```

No device identifier, user token, retrospective predictions or raw client
history is transmitted. The engine must use its own server-side verified
football data, odds and identical official analysis/selection pipeline.

## Response contract

```
{"protocol":"goalvdline-official-coupon-v1","officialEngine":true,
 "revision":"<pinned source revision>","coupon":{"events":[...]}}
```

Each event has `fixtureId`, `market`, `marketProbability`, future ISO
`kickoffAt`, and optional **real** `odds` from the provider. The bridge and
coordinator independently validate every event. No synthetic selections,
quotes or odds are generated here. HTTP 200 only on completed valid output;
otherwise the worker retries without exposing secrets.

## Release gate

Before enabling AutoSchedina: port the full existing Flutter analysis pipeline
and match/odds providers to a headless official engine, verify **golden parity
fixtures** (same inputs -> same ranked selections and confidence) against the
Flutter app, conduct signed iOS/APNs device tests, and configure an external
schedule for the worker. P15 does not claim those requirements are complete.
