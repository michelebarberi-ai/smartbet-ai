# Build 67 — Quarto cervello Meta AI (SHADOW)

**State:** feature code and tests only. Build 66 is the last authorized
TestFlight release. No Render deployment, Neon migration, paid service, new
push notification, or automatic coupon modification.

## What it actually is

This fourth brain is a **dependent meta-ensemble** of:
- SmartBet native market probabilities;
- Diego AI's own native market probabilities;
- mathematical GoalVdLine simulator probabilities (shared xG provenance).

It is *not* a new fully independent trained model. It can estimate, store and
compare its own prospective market probabilities for later calibration, but
cannot pick a coupon in production. The UI must say SHADOW.

## Algorithm (version META_B67_V1)

1. Only match the exact same fixture and the exact same full-time market;
   supported: `1`, `X`, `2`, `GOAL`, `NO GOAL`, `OVER 2.5`,
   `UNDER 2.5`. Never compare Goal with an unrelated Over or handicap.
2. Require both independently produced sporting probability vectors,
   one from SmartBet and one from Diego, with valid normalised market families.
   No Diego → no meta estimate; no fabricated fallback.
3. Use 50/50 between the two parent engines when history is insufficient.
   When **both** have segment-specific, prospective, verified MEI scores
   (minimum 100 results over 14 distinct days), tilt within 40/60–60/40.
   Only scores based on results verifiably known before this forecast are used.
4. If a valid simulator probability exists with known xG source, blend it
   into **its parent's weight** (25% of that weight), not as another independent
   vote. Missing/unknown origin means 0% simulator weight.
5. Forecast = bounded weighted average of probabilities, no bookmaker odds,
   stake, expected-value booster, ranking-to-coupon, or certainty inflation.
6. A parent-engine gap of 20+ percentage points is flagged as divergent,
   NOT converted into a supposedly safe prediction.
7. A first-in-time pre-match snapshot is persisted with engine `metaAi`
   and `META_B67_V1_...` classification. The exact first snapshot is immutable
   on repeated analysis; the official existing result resolver later settles it.
8. The existing MEI pipeline can then observe Meta AI's genuine future
   outcomes. Do not reinterpret retrospective copies as prospective validation.

## Guardrails

- Historical records used for training weights must have coherent
  settlement status against the observed match score, verified timestamps
  and the same country / league / market.
- The fourth engine is deliberately excluded from the B66 three-engine
  comparison, from prospective Neon mobile uploads, and from the legacy
  retrospective upload format.
- `allowedForLiveSelection == false` is a hard-coded property.
- Not yet able to prove that the fourth engine outperforms SmartBet/Diego.
  This requires paired, prospective out-of-sample evaluation on identical
  fixture/market events, with confidence intervals and adequate sample.
- No lookahead, post-match reforecast, or independent-confirmation claim.

## Where it appears

- The existing **Analisi motori AI** expansion shows its SHADOW estimate
  when a matching locally persisted forecast exists.
- **Intelligenza e apprendimento** shows number of stored meta forecasts,
  fixtures and settled records.
- **Storico analisi** adds a separate Meta AI filter and explains provenance.
- The MEI / league-reliability panels label it as a fourth SHADOW engine.

## Quality

`flutter analyze --no-pub --no-fatal-infos`

`flutter test --no-pub --reporter compact`

`npm --prefix backend test`

The feature QA is at
`.github/workflows/b67-fourth-brain-shadow-qa.yml`. It cannot upload
an iOS build to TestFlight. A separate GitHub release branch, version bump,
full release gates and explicit release authorization remain necessary.
