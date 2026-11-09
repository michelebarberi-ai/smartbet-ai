# GoalVdLine B45 — AutoCoupon worker (P10)

The `/learning/v1/auto-coupon/worker/run` endpoint is registered on the **dedicated**
learning service, but **disabled by default**. It is not a cron job, does not
send APNs pushes, and cannot produce coupons without a server-side adapter
that invokes the **same verified official engine** as the Flutter application.

Required gates (all must be configured **server-side**, never in the app):

- Learning and mobile ingest flags, plus `AUTO_COUPON_PREFERENCES_ENABLED=true`.
- `AUTO_COUPON_WORKER_ENABLED=true`.
- `AUTO_COUPON_WORKER_TOKEN` — an independent random secret of at least 32 chars.
- `generateOfficialCoupon` — a function injected into `createLearningOnlyApp`
  that returns real model-backed coupon selections in the P6 format.

The worker endpoint accepts POST JSON `{ "limit": 20, "afterSubjectHash": null }`
(maximum 25 per request), authenticated with the `x-goalvdline-worker-token`
header. On success, a trusted scheduled job can follow `nextCursor` until the
batch finishes. Response includes only counts/status and hashed cursor.

**Important:** Do not enable the flag or create a cron schedule until the
matching official generator is actually available and tested. Test fixtures
are not production generators. `autoCouponGenerationEnabled` and
`autoCouponPushEnabled` remain `false` in the status API until the complete
scheduler/generator/push pipeline is deployed and independently verified.

The iOS app must never contain `AUTO_COUPON_WORKER_TOKEN` or any admin key.
