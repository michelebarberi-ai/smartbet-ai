# GoalVdLine B79 — CORE quote sanity release

- Core market estimates are ranked by sporting model only; quoted odds participate only in final validation.
- Final local Auditor quarantines extreme positive model-vs-price discrepancies; the fixture can use the next sporting-ranked quoted market rather than a dubious Asian handicap.
- Signed Asian half-goal handicap conditions are comparable with Diego AI, and positive lines display a `+` sign in app and exported coupons.
- AFC Champions League display region is Asia; fixture identity and Italian schedule filtering are unchanged.
- Regression coverage includes original odd/probability examples, quote sign mapping, and release security contracts.

Build: 1.2.5+79. Source QA: backend and full Flutter suites passed on release candidate. The signed TestFlight workflow has mandatory backend, Flutter, analyzer, signing and Apple upload stages. The Build 78 backup remains available at `backup/build-78-pre-b79`.
