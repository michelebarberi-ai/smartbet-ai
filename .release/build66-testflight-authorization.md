# GoalVdLine / SmartBet AI — Build 66 TestFlight authorization

Release version: `1.2.5+66`.
Release branch: `release/b66-testflight`.
Based on reviewed `feature/b66-three-engine-neon-sync` branch.
QA run: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/44308281570
QA result: success — Node backend regression, Flutter analysis,
targeted tests, full Flutter regression.
Neon staging migration completed and verified with temporary probes.
Neon production intentionally unchanged.
Render production simulator ingest flags intentionally unchanged/off.
No new paid Render or Neon service.
The Build 66 TestFlight upload is initiated by this exact commit message
through `.github/workflows/ios-testflight.yml`, GitHub only.
This authorization covers the iOS TestFlight build, NOT a production
database migration, backend rollout or new recurring infrastructure costs.
