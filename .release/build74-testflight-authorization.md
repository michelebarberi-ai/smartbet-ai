# GoalVdLine — Build 74 TestFlight authorization

Date: 19 November 2026
Version: 1.2.5+74
Release branch: release/b74-testflight

Authorized changes:
- API budget: serialize client sports-request pacing and share same-team
  statistics queries; honor temporary provider cooldown windows.
- Restore country/competition labels on unquoted AI estimates.
- Combinazioni: apply Palinsesto Italia and user-selected competitions
  before statistical and advanced analysis, not only after quote lookup.
- Make selection counts reflect that same filtered set; explicitly distinguish
  zero candidate fixtures from temporarily unavailable bookmaker quotes.

QA:
- B74 Flutter static analysis and full regression suite: success
  https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/44468463668
- Combinazioni filter-first Flutter analysis and full regression suite: success
  https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/44472826382
- Existing TestFlight signing profile confirmed Apple distribution + APNs production.

This commit authorizes exactly one GitHub Actions Build 74 TestFlight upload.
It does NOT activate scheduled APNs notifications, any new API subscriptions,
or paid Render services.
