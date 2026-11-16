# GoalVdLine iOS 1.2.5 (Build 60) — Diego data coverage

The owner requested correction of Diego AI's N/D results seen after Build 59.

## Changes
- Diego explains why its forecast is unavailable, separating missing IDs, invalid fixture dates, incomplete historical dossier and temporary errors.
- Corrects historical data filtering that excluded Under 21 leagues, with explicit youth fixture identification, including U21 teams playing Premier League Cup.
- National teams may use only real pre-kickoff outcomes of the SAME official competition with at least five finished matches, conservative confidence <=55%; NO unrelated competitions or fictitious xG.
- Failed statistical lookups in both TeamDataResolver and HistoricalTeamService expire after 3 minutes instead of remaining unavailable for the full session.
- Keeps betting odds secondary and does NOT change SmartBet probabilities, quote thresholds, official coupon gating or Auditor vetoes.
- No new subscriptions, Neon migrations, mail providers or SMS. User-facing owner login remains disabled server-side until secure admin onboarding is configured.

## QA
- B60 full Flutter static+regression suite: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/43815706438
- iOS release pipeline repeats dedicated Diego tests before archive/upload.
- The feature is still dependent on actual API coverage; no guarantee every U21/national fixture has sufficient reliable data.
- TestFlight staging only, no public App Store release.
