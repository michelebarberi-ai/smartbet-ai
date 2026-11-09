# B45 P13 — Push dispatch after coupon storage (staging, OFF)

`POST /learning/v1/auto-coupon/worker/push` is a **separate**, authenticated
worker endpoint. It sends at most one *accepted* APNs push for each registered
client/day with an already saved `ready` coupon, using a durable claim/retry
record. It does not generate coupons, run on a timer, or send anything by
itself. The trusted scheduler must call the official generation worker FIRST,
then this push worker, and iterate the `nextCursor` for larger batches.

Endpoint JSON: `{ "limit": 20, "afterSubjectHash": null }` (max 25), header
`x-goalvdline-worker-token: ...` (server-to-server only). Never put the worker
secret or Apple credentials on the iPhone.

Flags required on the dedicated learning server (do NOT turn on yet):
- learning enabled + mobile ingest + auto-coupon preferences enabled
- `AUTO_COUPON_WORKER_ENABLED=true` and a proper worker token
- a verified `generateOfficialCoupon` adapter, equivalent to the Flutter engine
- `AUTO_COUPON_PUSH_REGISTRATION_ENABLED=true`
- `AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY` (64 hex chars, server only)
- `AUTO_COUPON_PUSH_ENABLED=true`
- APNs key ID, team ID, bundle ID, P-256 signing key and correct environment

All gates default closed. TestFlight uses **production** APNs. iPhone registration
remains voluntary. A push is attempted only for a **current Rome-day**, ready,
unexpired coupon with a valid registered APNs token. Apple acceptance is not
proof of delivery. The `apns-collapse-id` reduces but cannot absolutely
prevent duplicate notices when network outcomes are ambiguous.

Next prerequisites before enabling: official server-side generator equivalence,
trusted cron/worker schedule, APNs capability/provisioning, end-to-end device
checks, monitoring and guarded rollout. No changes to the paid production API.
