import csv
from pathlib import Path

FILES = [
    (
        "CAMPIONE PRINCIPALE",
        Path("tool/goalvdline_match_engine_backtest_results.csv"),
    ),
    (
        "CAMPIONE INDIPENDENTE",
        Path("tool/goalvdline_match_engine_validation_results.csv"),
    ),
]


def calculate_confidence(row):
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

    best_clarity = (
        ((best - (1.0 / 3.0)) / (2.0 / 3.0)) * 100.0
    )
    best_clarity = max(0.0, min(100.0, best_clarity))

    separation_clarity = (
        ((best - second) / 0.40) * 100.0
    )
    separation_clarity = max(
        0.0,
        min(100.0, separation_clarity),
    )

    data_confidence = float(row["data_confidence"])

    confidence = (
        data_confidence * 0.35
        + best_clarity * 0.25
        + separation_clarity * 0.40
    )

    return max(1, min(95, round(confidence)))


def load(path):
    rows = []

    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        for row in reader:
            rows.append({
                "hit": row["hit"].lower() == "true",
                "confidence": calculate_confidence(row),
            })

    return rows


def report(name, rows):
    print()
    print("=" * 72)
    print(name)
    print("=" * 72)
    print(f"Partite: {len(rows)}")

    buckets = [
        (0, 39),
        (40, 49),
        (50, 59),
        (60, 69),
        (70, 79),
        (80, 95),
    ]

    print()
    print("--- ACCURATEZZA PER FASCIA ---")

    for low, high in buckets:
        subset = [
            r for r in rows
            if low <= r["confidence"] <= high
        ]

        if not subset:
            continue

        hits = sum(r["hit"] for r in subset)

        print(
            f"{low:02d}-{high:02d}: "
            f"{hits}/{len(subset)} "
            f"({hits/len(subset)*100:.1f}%)"
        )

    print()
    print("--- ACCURATEZZA SOPRA SOGLIA ---")

    for threshold in (40, 45, 50, 55, 60, 65, 70):
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
            f"({hits/len(subset)*100:.1f}%)"
        )

    print()
    print("--- DISTRIBUZIONE ---")

    values = [r["confidence"] for r in rows]

    print(
        f"Min: {min(values)} | "
        f"Media: {sum(values)/len(values):.1f} | "
        f"Max: {max(values)}"
    )


for name, path in FILES:
    report(name, load(path))
