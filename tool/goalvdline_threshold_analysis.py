import csv
from pathlib import Path

path = Path("tool/goalvdline_match_engine_backtest_results.csv")

rows = []

with path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for row in reader:
        probabilities = {
            "1": float(row["p1"]),
            "X": float(row["px"]),
            "2": float(row["p2"]),
        }

        predicted = row["predicted"]
        probability = probabilities[predicted]

        rows.append({
            "match": row["match"],
            "actual": row["actual"],
            "predicted": predicted,
            "hit": row["hit"].lower() == "true",
            "probability": probability,
            "confidence": int(row["prediction_confidence"]),
        })

print()
print("=" * 70)
print("GOALVDLINE - ANALISI SOGLIE BACKTEST")
print("=" * 70)
print(f"Partite disponibili: {len(rows)}")

print()
print("--- PERFORMANCE PER ESITO PRONOSTICATO ---")

for outcome in ("1", "X", "2"):
    subset = [r for r in rows if r["predicted"] == outcome]

    if not subset:
        continue

    hits = sum(r["hit"] for r in subset)

    print(
        f"{outcome}: "
        f"{hits}/{len(subset)} "
        f"({hits / len(subset) * 100:.1f}%)"
    )

print()
print("--- SOGLIA CONFIDENCE ---")

for threshold in (50, 55, 60, 65, 70, 75, 80):
    subset = [
        r for r in rows
        if r["confidence"] >= threshold
    ]

    if not subset:
        continue

    hits = sum(r["hit"] for r in subset)

    print(
        f"Conf >= {threshold}: "
        f"{hits}/{len(subset)} "
        f"({hits / len(subset) * 100:.1f}%)"
    )

print()
print("--- SOGLIA PROBABILITÀ ESITO SCELTO ---")

for threshold in (0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70):
    subset = [
        r for r in rows
        if r["probability"] >= threshold
    ]

    if not subset:
        continue

    hits = sum(r["hit"] for r in subset)

    print(
        f"Prob >= {threshold * 100:.0f}%: "
        f"{hits}/{len(subset)} "
        f"({hits / len(subset) * 100:.1f}%)"
    )

print()
print("--- COMBINAZIONE CONFIDENCE + PROBABILITÀ ---")

results = []

for confidence in (50, 55, 60, 65, 70, 75, 80):
    for probability in (0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70):

        subset = [
            r for r in rows
            if r["confidence"] >= confidence
            and r["probability"] >= probability
        ]

        if len(subset) < 3:
            continue

        hits = sum(r["hit"] for r in subset)
        accuracy = hits / len(subset)

        results.append(
            (
                accuracy,
                len(subset),
                hits,
                confidence,
                probability,
            )
        )

# Prima accuratezza, poi campione più grande.
results.sort(
    key=lambda item: (item[0], item[1]),
    reverse=True,
)

for accuracy, total, hits, confidence, probability in results[:15]:
    print(
        f"Conf >= {confidence:2d} + "
        f"Prob >= {probability * 100:2.0f}%  "
        f"=> {hits}/{total} "
        f"({accuracy * 100:.1f}%)"
    )

print()
print("--- PARTITE CON CONFIDENCE >= 70 ---")

high_conf = [
    r for r in rows
    if r["confidence"] >= 70
]

high_conf.sort(
    key=lambda r: (
        r["confidence"],
        r["probability"],
    ),
    reverse=True,
)

for r in high_conf:
    marker = "✓" if r["hit"] else "✗"

    print(
        f"{marker} "
        f"conf {r['confidence']:2d} | "
        f"prob {r['probability'] * 100:5.1f}% | "
        f"{r['predicted']} | "
        f"{r['match']} | "
        f"reale {r['actual']}"
    )

print()
print("=" * 70)
