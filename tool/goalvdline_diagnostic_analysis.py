import csv
from collections import Counter
from pathlib import Path

path = Path("tool/goalvdline_match_engine_backtest_results.csv")

rows = []

with path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for row in reader:
        predicted = row["predicted"]
        actual = row["actual"]

        probabilities = {
            "1": float(row["p1"]),
            "X": float(row["px"]),
            "2": float(row["p2"]),
        }

        rows.append({
            "match": row["match"],
            "actual": actual,
            "predicted": predicted,
            "probabilities": probabilities,
            "max_probability": probabilities[predicted],
            "confidence": int(row["prediction_confidence"]),
        })

print()
print("=" * 70)
print("GOALVDLINE - DIAGNOSTICA 1X2")
print("=" * 70)

actual_counts = Counter(r["actual"] for r in rows)
predicted_counts = Counter(r["predicted"] for r in rows)

print()
print("--- DISTRIBUZIONE REALE ---")
for outcome in ("1", "X", "2"):
    count = actual_counts[outcome]
    pct = count / len(rows) * 100
    print(f"{outcome}: {count}/{len(rows)} ({pct:.1f}%)")

print()
print("--- DISTRIBUZIONE PRONOSTICATA ---")
for outcome in ("1", "X", "2"):
    count = predicted_counts[outcome]
    pct = count / len(rows) * 100
    print(f"{outcome}: {count}/{len(rows)} ({pct:.1f}%)")

print()
print("--- MATRICE ACTUAL -> PREDICTED ---")

for actual in ("1", "X", "2"):
    subset = [r for r in rows if r["actual"] == actual]

    values = Counter(r["predicted"] for r in subset)

    print(
        f"Reale {actual}: "
        f"pred 1={values['1']} | "
        f"pred X={values['X']} | "
        f"pred 2={values['2']}"
    )

print()
print("--- PROBABILITÀ MEDIE ASSEGNATE ---")

for actual in ("1", "X", "2"):
    subset = [r for r in rows if r["actual"] == actual]

    if not subset:
        continue

    avg1 = sum(r["probabilities"]["1"] for r in subset) / len(subset)
    avgx = sum(r["probabilities"]["X"] for r in subset) / len(subset)
    avg2 = sum(r["probabilities"]["2"] for r in subset) / len(subset)

    print(
        f"Quando il reale è {actual}: "
        f"1={avg1*100:.1f}% "
        f"X={avgx*100:.1f}% "
        f"2={avg2*100:.1f}%"
    )

print()
print("--- CALIBRAZIONE DELLA PROBABILITÀ MASSIMA ---")

bins = [
    (0.30, 0.40),
    (0.40, 0.50),
    (0.50, 0.60),
    (0.60, 0.70),
    (0.70, 0.80),
    (0.80, 1.01),
]

for low, high in bins:
    subset = [
        r for r in rows
        if low <= r["max_probability"] < high
    ]

    if not subset:
        continue

    hits = sum(r["actual"] == r["predicted"] for r in subset)

    avg_prob = (
        sum(r["max_probability"] for r in subset)
        / len(subset)
    )

    hit_rate = hits / len(subset)

    print(
        f"{low*100:2.0f}-{high*100:2.0f}%: "
        f"n={len(subset):2d} | "
        f"prob media={avg_prob*100:5.1f}% | "
        f"reale={hit_rate*100:5.1f}%"
    )

print()
print("--- ERRORI AD ALTA PROBABILITÀ >= 60% ---")

errors = [
    r for r in rows
    if r["max_probability"] >= 0.60
    and r["actual"] != r["predicted"]
]

errors.sort(
    key=lambda r: r["max_probability"],
    reverse=True,
)

for r in errors:
    print(
        f"{r['max_probability']*100:5.1f}% | "
        f"conf {r['confidence']:2d} | "
        f"pred {r['predicted']} | "
        f"reale {r['actual']} | "
        f"{r['match']}"
    )

print()
print("=" * 70)
