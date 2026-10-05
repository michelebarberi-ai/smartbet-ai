import csv
from pathlib import Path

FILES = [
    Path("tool/goalvdline_match_engine_backtest_results.csv"),
    Path("tool/goalvdline_match_engine_validation_results.csv"),
]

observations = []


def certainty(probability):
    # 50% = mercato completamente equilibrato
    # 100% = scenario estremamente netto
    return abs(probability - 0.5) / 0.5 * 100.0


def add_observation(
    *,
    family,
    market,
    probability,
    actual,
    data_confidence,
):
    observations.append({
        "family": family,
        "market": market,
        "probability": probability,
        "actual": actual,
        "data": data_confidence,
        "clarity": certainty(probability),
    })


for path in FILES:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        for row in reader:
            actual = row["actual"]

            p1 = float(row["p1"])
            px = float(row["px"])
            p2 = float(row["p2"])

            data = float(row["data_confidence"])

            # ====================================================
            # DOPPIA CHANCE
            # scegliamo la DC più probabile
            # ====================================================

            dc = {
                "1X": (
                    p1 + px,
                    actual in ("1", "X"),
                ),
                "X2": (
                    px + p2,
                    actual in ("X", "2"),
                ),
                "12": (
                    p1 + p2,
                    actual in ("1", "2"),
                ),
            }

            dc_market = max(
                dc,
                key=lambda key: dc[key][0],
            )

            dc_probability, dc_actual = dc[dc_market]

            add_observation(
                family="DOUBLE CHANCE",
                market=dc_market,
                probability=dc_probability,
                actual=dc_actual,
                data_confidence=data,
            )

            # ====================================================
            # OVER / UNDER 2.5
            # ====================================================

            p_over = float(row["p_over25"])
            actual_over = (
                row["actual_over25"].lower() == "true"
            )

            if p_over >= 0.5:
                market = "OVER 2.5"
                probability = p_over
                hit = actual_over
            else:
                market = "UNDER 2.5"
                probability = 1.0 - p_over
                hit = not actual_over

            add_observation(
                family="O/U 2.5",
                market=market,
                probability=probability,
                actual=hit,
                data_confidence=data,
            )

            # ====================================================
            # GOAL / NO GOAL
            # ====================================================

            p_goal = float(row["p_goal"])
            actual_goal = (
                row["actual_goal"].lower() == "true"
            )

            if p_goal >= 0.5:
                market = "GOAL"
                probability = p_goal
                hit = actual_goal
            else:
                market = "NO GOAL"
                probability = 1.0 - p_goal
                hit = not actual_goal

            add_observation(
                family="GOAL/NOGOAL",
                market=market,
                probability=probability,
                actual=hit,
                data_confidence=data,
            )


def score_balanced(row):
    return (
        row["data"] * 0.35
        + row["clarity"] * 0.65
    )


def score_data_heavy(row):
    return (
        row["data"] * 0.50
        + row["clarity"] * 0.50
    )


def score_clarity_heavy(row):
    return (
        row["data"] * 0.25
        + row["clarity"] * 0.75
    )


def score_guard(row):
    data_guard = 0.70 + (
        row["data"] / 100.0 * 0.30
    )

    return row["clarity"] * data_guard


FORMULAS = {
    "35 DATA / 65 CLARITY": score_balanced,
    "50 DATA / 50 CLARITY": score_data_heavy,
    "25 DATA / 75 CLARITY": score_clarity_heavy,
    "DATA GUARD": score_guard,
}


def auc(scored):
    positives = [
        score for score, hit in scored
        if hit
    ]

    negatives = [
        score for score, hit in scored
        if not hit
    ]

    if not positives or not negatives:
        return 0.0

    wins = 0.0
    comparisons = 0

    for positive in positives:
        for negative in negatives:
            comparisons += 1

            if positive > negative:
                wins += 1
            elif positive == negative:
                wins += 0.5

    return wins / comparisons


print()
print("=" * 76)
print("DIEGOAI - MARKET CONFIDENCE ANALYSIS")
print("=" * 76)
print(f"Osservazioni: {len(observations)}")

for name, formula in FORMULAS.items():
    scored = [
        (
            formula(row),
            row["actual"],
        )
        for row in observations
    ]

    scored.sort(
        key=lambda item: item[0],
        reverse=True,
    )

    print()
    print(f"--- {name} ---")
    print(f"AUC: {auc(scored):.3f}")

    for top in (25, 50, 75, 100, 150):
        subset = scored[:top]

        hits = sum(
            hit
            for _, hit in subset
        )

        print(
            f"Top {top:3d}: "
            f"{hits}/{len(subset)} "
            f"({hits/len(subset)*100:.1f}%)"
        )


print()
print("--- PERFORMANCE PER FAMIGLIA ---")

for family in (
    "DOUBLE CHANCE",
    "O/U 2.5",
    "GOAL/NOGOAL",
):
    subset = [
        row
        for row in observations
        if row["family"] == family
    ]

    hits = sum(
        row["actual"]
        for row in subset
    )

    avg_probability = sum(
        row["probability"]
        for row in subset
    ) / len(subset)

    print(
        f"{family:15s}: "
        f"{hits}/{len(subset)} "
        f"({hits/len(subset)*100:.1f}%) | "
        f"prob media {avg_probability*100:.1f}%"
    )

print()
print("=" * 76)
