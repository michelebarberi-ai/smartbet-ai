# GoalVdLine / SmartBet AI — Build 71 TestFlight authorization

Version: `1.2.5+71`
Release branch: `release/b71-testflight`
Tested feature: `feature/b71-italian-calendar-default-odds-cooldown`
Tested SHA: `62841742ee854798bebf6c512baae1c9eacd4900`
Full QA: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/44396160897
Full QA conclusion: SUCCESS (backend, Flutter analyzer, targeted B71 tests
and entire Flutter regression).

Changes:
- Global Italian Material/Widgets/Cupertino date picker labels; explicit
  Italian calendar locale and genuine 'FINE SETTIMANA' period label.
- Italian sports schedule and Italian-registered bookmaker filtering ON by
  default and still user-toggleable.
- Provider-wide API-Football quota/cooldown classification; bounded
  Retry-After honored client-side, no repeated odds HTTP requests during
  pause, no inferred bookmaker availability or fabricated quote.
- Clearer read-only previews: primary regular sporting market rather
  than repetitive broad OR union probabilities near 99%.
- No change to minimum odds >1.20 or selected market probability gate.
- No Neon or Render configuration change, no new paid service.

The observed Render 429 and proxy 503 are caused by the provider's
request limits and circuit cooldown, not by the absence of bookmaker
markets. Additional provider capacity, when necessary, is NOT activated.

This exact commit authorizes the signed GitHub-only TestFlight workflow.
