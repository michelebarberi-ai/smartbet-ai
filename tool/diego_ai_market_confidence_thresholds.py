import csv
from pathlib import Path

FILES = [
    Path("tool/goalvdline_match_engine_backtest_results.csv"),
    Path("tool/goalvdline_match_engine_validation_results.csv"),
]

rows = []


def market_confidence(probability, data_confidence):
    clarity = abs(probability - 0.5) / 0.5 * 100.0

    score = (
        data_confidence * 0.35
        + clarity * 0.65
    )

    return max(1, min(95, round(score)))


def add(family, probability, hit, data):
    rows.append({
        "family": family,
        "probability": probability,
        "hit": hit,
        "confidence": market_confidence(
            probability,
            data,
        ),
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
            # DOPPIA CHANCE PIÙ PROBABILE
            # ====================================================

            dc = {
                "1X": (p1 + px, actual in ("1", "X")),
                "X2": (px + p2, actual in ("X", "2")),
                "12": (p1 + p2, actual in ("1", "2")),
            }

            selected = max(
                dc,
                key=lambda key: dc[key][0],
            )

            probability, hit = dc[selected]

            add(
                "DOUBLE CHANCE",
                probability,
                hit,
                data,
            )

            # ====================================================
            # OVER / UNDER 2.5
            # ====================================================

            p_over = float(row["p_over25"])
            actual_over = (
                row["actual_over25"].lower() == "true"
            )

            if p_over >= 0.5:
                add(
                    "O/U 2.5",
                    p_over,
                    actual_over,
                    data,
                )
            else:
                add(
                    "O/U 2.5",
                    1.0 - p_over,
                    not actual_over,
                    data,
                )

            # ====================================================
            # GOAL / NO GOAL
            # ====================================================

            p_goal = float(row["p_goal"])
            actual_goal = (
                row["actual_goal"].lower() == "true"
            )

            if p_goal >= 0.5:
                add(
                    "GOAL/NOGOAL",
                    p_goal,
                    actual_goal,
                    data,
                )
            else:
                add(
                    "GOAL/NOGOAL",
                    1.0 - p_goal,
                    not actual_goal,
                    data,
                )


def report(title, subset):
    print()
    print(title)
    print("-" * 72)

    for threshold in (
        35,
        40,
        45,
        50,
        55,
        60,
        65,
        70,
    ):
        selected = [
            r for r in subset
            if r["confidence"] >= threshold
        ]

        if not selected:
            continue

        hits = sum(r["hit"] for r in selected)

        print(
            f"Conf >= {threshold:2d}: "
            f"{hits:3d}/{len(selected):3d} "
            f"({hits/len(selected)*100:5.1f}%)"
        )

    print()
    print("FASCE")

    for low, high in (
        (0, 39),
        (40, 49),
        (50, 59),
        (60, 69),
        (70, 95),
    ):
        selected = [
            r for r in subset
            if low <= r["confidence"] <= high
        ]

        if not selected:
            continue

        hits = sum(r["hit"] for r in selected)

        print(
            f"{low:02d}-{high:02d}: "
            f"{hits:3d}/{len(selected):3d} "
            f"({hits/len(selected)*100:5.1f}%)"
        )


print()
print("=" * 72)
print("DIEGOAI - MARKET CONFIDENCE THRESHOLDS")
print("=" * 72)
print(f"Osservazioni totali: {len(rows)}")

report("TUTTI I MERCATI", rows)

for family in (
    "DOUBLE CHANCE",
    "O/U 2.5",
    "GOAL/NOGOAL",
):
    report(
        family,
        [r for r in rows if r["family"] == family],
    )

print()
print("=" * 72)
