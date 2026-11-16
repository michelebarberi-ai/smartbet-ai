# Build 62 — explicit TestFlight authorization

The app owner explicitly authorized uploading GoalVdLine iOS 1.2.5+62 to TestFlight through the existing GitHub Actions pipeline.

- Release branch: `release/b62-testflight`
- QA source SHA: `07b5653ceaff19bbf51f133880799d1015e13edc`
- Full Flutter staging regression: success — https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/43952935526
- The macOS release job must pass analysis and full Flutter regression, then use existing App Store Connect signing secrets and upload.
- No new server costs or changes, no public App Store submission.
- See `docs/B62_TESTFLIGHT_RELEASE.md` for scope and limitations.
