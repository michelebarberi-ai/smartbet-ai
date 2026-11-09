# Build 45 P11 — APNs sender (server staging)

This phase adds a **disabled-by-default APNs transport** and unit tests. It does
NOT register iPhones, set up Apple entitlements, schedule jobs, or send any push.
The official Flutter coupon generator must be integrated and validated first.

The provider uses Node's built-in `node:http2` and `node:crypto` (ES256 JWT).
No push credentials or personal data belong in the Flutter repository.

Before APNs can be enabled in a later phase, configure these **server-side**
environment variables in Render (do not commit their values):

- `AUTO_COUPON_PUSH_ENABLED=true` (currently leave false)
- `AUTO_COUPON_WORKER_ENABLED=true` (currently leave false)
- `APNS_KEY_ID`: the 10-character Apple key ID
- `APNS_TEAM_ID`: the 10-character Apple Developer Team ID
- `APNS_BUNDLE_ID`: the *actual* signed iOS bundle identifier
- `APNS_ENVIRONMENT=production` for TestFlight/App Store, `sandbox` only for dev
- `APNS_PRIVATE_KEY_BASE64`: base64 encoding of the APNs `.p8` private key

Do **not** enable either worker or push during P11. A later phase must add
user-consented iOS device-token registration, secure encrypted-at-rest token
storage, push queue/idempotency and hooking the notifier to the verified
coupon-ready event; APNs HTTP 200 indicates acceptance, not device delivery.

Test with:

```bash
node --test backend/test/auto_coupon_apns_provider.test.js
```
