import csv
import math
from pathlib import Path

path = Path("tool/goalvdline_match_engine_backtest_results.csv")

rows = []

with path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for row in reader:
        probs = sorted(
            [
                float(row["p1"]),
                float(row["px"]),
                float(row["p2"]),
            ],
            reverse=True,
        )

        best = probs[0]
        second = probs[1]

        margin = best - second

        entropy = 0.0

        for p in probs:
            if p > 0:
                entropy -= p * math.log(p)

        # 0 = massima incertezza
        # 100 = distribuzione molto netta
        entropy_clarity = (
            1.0 - entropy / math.log(3)
        ) * 100.0

        rows.append({
            "hit": row["hit"].lower() == "true",
            "data": int(row["data_confidence"]),
            "confidence": int(row["prediction_confidence"]),
            "best": best * 100.0,
            "margin": margin * 100.0,
            "entropy_clarity": entropy_clarity,
        })

def average(values):
    return sum(values) / len(values) if values else 0.0

correct = [r for r in rows if r["hit"]]
wrong = [r for r in rows if not r["hit"]]

print()
print("=" * 72)
print("GOALVDLINE - CONFIDENCE DIAGNOSTIC")
print("=" * 72)

print()
print("--- CORRETTE vs SBAGLIATE ---")

for key, label in [
    ("data", "Data confidence"),
    ("confidence", "Prediction confidence"),
    ("best", "Probabilità massima"),
    ("margin", "Distacco 1°-2°"),
    ("entropy_clarity", "Chiarezza entropia"),
]:
    a = average([r[key] for r in correct])
    b = average([r[key] for r in wrong])

    print(
        f"{label:24s} "
        f"corrette={a:5.1f} | "
        f"sbagliate={b:5.1f} | "
        f"delta={a-b:+5.1f}"
    )

print()
print("--- TOP PER PREDICTION CONFIDENCE ---")

ordered = sorted(
    rows,
    key=lambda r: r["confidence"],
    reverse=True,
)

for top in (5, 10, 15, 20, 25):
    subset = ordered[:top]
    hits = sum(r["hit"] for r in subset)

    print(
        f"Top {top:2d}: "
        f"{hits}/{len(subset)} "
        f"({hits/len(subset)*100:.1f}%)"
    )

print()
print("--- TOP PER PROBABILITÀ MASSIMA ---")

ordered = sorted(
    rows,
    key=lambda r: r["best"],
    reverse=True,
)

for top in (5, 10, 15, 20, 25):
    subset = ordered[:top]
    hits = sum(r["hit"] for r in subset)

    print(
        f"Top {top:2d}: "
        f"{hits}/{len(subset)} "
        f"({hits/len(subset)*100:.1f}%)"
    )

print()
print("--- TOP PER DISTACCO 1°-2° ---")

ordered = sorted(
    rows,
    key=lambda r: r["margin"],
    reverse=True,
)

for top in (5, 10, 15, 20, 25):
    subset = ordered[:top]
    hits = sum(r["hit"] for r in subset)

    print(
        f"Top {top:2d}: "
        f"{hits}/{len(subset)} "
        f"({hits/len(subset)*100:.1f}%)"
    )

print()
print("--- TOP PER CHIAREZZA ENTROPIA ---")

ordered = sorted(
    rows,
    key=lambda r: r["entropy_clarity"],
    reverse=True,
)

for top in (5, 10, 15, 20, 25):
    subset = ordered[:top]
    hits = sum(r["hit"] for r in subset)

    print(
        f"Top {top:2d}: "
        f"{hits}/{len(subset)} "
        f"({hits/len(subset)*100:.1f}%)"
    )

print()
print("=" * 72)
