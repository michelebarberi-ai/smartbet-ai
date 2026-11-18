# GoalVdLine / SmartBet AI — Build 69 GitHub TestFlight authorization

Release version: `1.2.5+69`
Release branch: `release/b69-testflight`
Tested feature: `feature/b69-audit-clarity`
Tested source SHA: `506e8c4207e3d3e02b0aa3ecca06b3b8502b108a`
Full CI: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/44351555019
Full CI conclusion: SUCCESS (backend, Flutter analyze, targeted odds/Auditor
tests, full Flutter regression).

Release scope:
- Quote feed diagnostics: HTTP status and quota/proxy/network categories.
- Limit concurrent odds lookup from 6 to 2, stop repeat systemic failures
  and clearly count fixtures not queried.
- Clarify local vs advanced Auditor, matched 1X2 comparisons.
- Explain that high union-market model probabilities are not validated
  historical hit rates.
- Keep >1.20 real odds threshold and >=65% selected sporting filter.
- Do not fabricate quotes, sportsbook availability or market probabilities.
- No Render service changes, Neon migration, new paid plan or Meta AI promotion.

This exact authorization commit enables the existing GitHub Actions
TestFlight release workflow, with all release tests before signing.
