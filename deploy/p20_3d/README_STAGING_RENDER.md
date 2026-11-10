# GoalVdLine B45 P20.3D — Render staging only

## Verified from the supplied source archive

- The project archive contained **no** `render.yaml`, `Dockerfile`, or Flutter version lock for Linux. The existing iOS workflow performs `flutter clone --branch stable` (not reproducibly pinned).
- The headless HTTP host originally listened exclusively on loopback; private Render services need a network-reachable port.
- The official engine adapter originally accepted only public HTTPS URLs. This patch adds a **strictly opt-in exception** for **one named private Render staging service**, not generic HTTP.
- The existing worker is disabled unless its four independent gates and other required values are valid. No background generation is enabled by this patch.

## Staging architecture

1. Private service `smartbet-b45-flutter-staging` running the original `SmartBetAutoCouponService` through the existing Flutter integration test, in a container with Node and Flutter; it listens on port 8799 and writes its job journal to the mounted disk.
2. Background worker `smartbet-b45-coupon-worker-staging`, outbound-only, invoking the existing Neon coordinator through the P20.3B lease/fencing mechanism.
3. A **separate staging Neon** database with the P20.3B migration, not the production database. No APNs flags.

The template is deliberately named `render.p20_3d.staging.example.yaml`, **not** `render.yaml`, to prevent automatic synchronization. DO NOT sync it yet: the disabled worker is designed to fail closed (and therefore does not stay healthy while disabled). The file is a reviewed starting template, not an immediately deployable production Blueprint.

## Required private setup before attempting a staging deployment

- Compare `flutter --version` on the developer Mac and choose an exact compatible **Flutter release tag** for `FLUTTER_REF` (not `stable`). Confirm its Docker Linux test runtime supports all app plugins and Flutter assets.
- Run a local Docker build using the Dockerfile first. Some projects require a `.env` Flutter asset: **do not embed secrets** or copy local `.env` into images. Audit `pubspec.yaml`, `main.dart`, all `dotenv` usages and asset paths. If the engine requires secrets, supply them at runtime via a safe server-only configuration and validate the app can load it without bundling credentials.
- Review `.dockerignore` behavior and audit the entire build context for secret files. This Dockerfile uses a Dockerfile-specific ignore, but unknown secret filenames in the repository may still be copied: do not deploy or build with unreviewed secrets.
- Create a random **URL-safe** secret of >= 32 characters for `AUTO_COUPON_HEADLESS_TOKEN`; do not use Render-generated standard base64 because the runner accepts only alphanumeric, `_` and `-` in the Bearer header. Never paste secrets in chat or commit them.
- Pin `AUTO_COUPON_HEADLESS_REVISION` and `AUTO_COUPON_OFFICIAL_ENGINE_REVISION` to the **same actual checked-out Git SHA**. The current `REVISION_PATTERN` allows 7–40 hexadecimal characters, but choose a full 40-character SHA. Ensure your Docker image builds that same Git commit; do not rely on moving branches.
- Ensure both Render services share workspace and region. Check the actual internal hostname returned by the Render `fromService ... hostport` reference against the intentionally restricted regex in `official_engine_client.js`.
- Internal `http://` carries bearer tokens over the **private Render network without end-to-end TLS**. This is a staging-only exception. For production, install TLS on the internal hop or use a separately reviewed HTTPS termination path; do not enable this staging HTTP exception in production.
- A persistent disk is attached to only one instance, and deploys/restarts interrupt ongoing Flutter jobs. Neon leases prevent stale writes, but Flutter compute may be repeated.

## Verification before enabling anything

```sh
node --test backend/test/auto_coupon_p20_3d_render_transport.test.js
node --test backend/test/auto_coupon_*.test.js backend/test/learning_mobile_auth.test.js backend/test/learning_retrospective.test.js backend/test/learning_routes.test.js
flutter test --reporter compact
flutter analyze --no-pub
```

Then run a Linux Docker build with a pinned Flutter tag, verify the P18 headless test process and its authentication, fail-closed errors, journal persistence across restart, and parity with the iOS output. Test Neon staging migration, two independent worker processes, consent revocation and lease recovery. APNs stays disabled.

### Release guard

The existing `.github/workflows/ios-testflight.yml` triggers on pushes to `feature/v1.2.4-simulation`; **do not push this branch merely to stage Render** until release orchestration is explicitly reviewed. A local Git commit does not trigger that workflow.
