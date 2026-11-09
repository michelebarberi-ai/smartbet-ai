# B45 P12 — iPhone APNs registration (staging)

- Opt-in only: iPhone calls register after a user tap and iOS notification permission.
- Server stores AES-256-GCM ciphertext (key from env, **never** in repository).
- Register requires active, already-synchronized AutoSchedina preferences.
- Revocation/unregister, disabling scheduled preferences, revoke/erase client delete registration.
- No automatic APNs messages or coupon generation are enabled by this patch.
- **Default: disabled** (`AUTO_COUPON_PUSH_REGISTRATION_ENABLED` absent/false).

When ready for a controlled TestFlight test, configure the server (not the app):

- `AUTO_COUPON_PUSH_REGISTRATION_ENABLED=true`
- `AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY=<64-character random hex, keep private>`
- `APNS_ENVIRONMENT=production` for TestFlight; `sandbox` only for development
- `AUTO_COUPON_PREFERENCES_ENABLED=true` and existing learning/mobile gates.

**iOS**: Enable **Push Notifications** for bundle `com.michelebarberi.smartbetai`
in Apple Developer and Xcode Signing & Capabilities, ensure the corresponding
provisioning profile and `aps-environment` entitlement exist in the signed
TestFlight build. This patch does not alter signing to avoid breaking the
existing GitHub workflow. Without that entitlement registration will fail closed.

Tests:
`node --test backend/test/auto_coupon_push_registration.test.js`
For iOS UI integration, also run Flutter tests and a signed iPhone build.
