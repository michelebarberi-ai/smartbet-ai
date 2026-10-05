import csv
import math
from collections import Counter
from pathlib import Path

path = Path("tool/goalvdline_match_engine_backtest_results.csv")

rows = []

with path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for row in reader:
        rows.append({
            "fixture_id": int(row["fixture_id"]),
            "match": row["match"],
            "actual": row["actual"],
            "p1": float(row["p1"]),
            "px": float(row["px"]),
            "p2": float(row["p2"]),
        })

rows.sort(key=lambda r: r["fixture_id"])


def adjust(row, draw_factor, away_factor):
    p1 = row["p1"]
    px = row["px"] * draw_factor
    p2 = row["p2"] * away_factor

    total = p1 + px + p2

    return {
        "1": p1 / total,
        "X": px / total,
        "2": p2 / total,
    }


def raw_probs(row):
    return {
        "1": row["p1"],
        "X": row["px"],
        "2": row["p2"],
    }


def metrics(items):
    if not items:
        return {
            "accuracy": 0.0,
            "brier": 0.0,
            "logloss": 0.0,
        }

    correct = 0
    brier = 0.0
    logloss = 0.0

    for actual, probs in items:
        predicted = max(
            probs,
            key=probs.get,
        )

        if predicted == actual:
            correct += 1

        for outcome in ("1", "X", "2"):
            target = 1.0 if outcome == actual else 0.0
            error = probs[outcome] - target
            brier += error * error

        probability = max(
            probs[actual],
            0.000001,
        )

        logloss += -math.log(probability)

    n = len(items)

    return {
        "accuracy": correct / n,
        "brier": brier / n,
        "logloss": logloss / n,
    }


# ============================================================
# BASELINE
# ============================================================

baseline_items = [
    (row["actual"], raw_probs(row))
    for row in rows
]

baseline = metrics(baseline_items)

# ============================================================
# CROSS VALIDATION 5-FOLD
# ============================================================
#
# Per ogni gruppo:
# - 4 gruppi servono per scegliere i fattori
# - il quinto gruppo viene tenuto fuori
#
# Quindi la partita testata NON viene usata per scegliere
# la correzione applicata a quella stessa partita.
# ============================================================

fold_count = 5

calibrated_items = []
calibrated_rows = []

chosen_parameters = []

for fold in range(fold_count):
    train = [
        row
        for index, row in enumerate(rows)
        if index % fold_count != fold
    ]

    test = [
        row
        for index, row in enumerate(rows)
        if index % fold_count == fold
    ]

    best = None

    # HOME resta il riferimento = 1.0.
    #
    # Testiamo:
    # X:   1.0 -> 2.0
    # AWAY 0.5 -> 1.1
    #
    # Non sono ancora pesi di produzione:
    # servono solo a capire la direzione del bias.
    for draw_step in range(10, 21):
        draw_factor = draw_step / 10.0

        for away_step in range(5, 12):
            away_factor = away_step / 10.0

            train_items = [
                (
                    row["actual"],
                    adjust(
                        row,
                        draw_factor,
                        away_factor,
                    ),
                )
                for row in train
            ]

            score = metrics(train_items)

            candidate = (
                score["logloss"],
                score["brier"],
                -score["accuracy"],
                draw_factor,
                away_factor,
            )

            if best is None or candidate < best:
                best = candidate

    _, _, _, draw_factor, away_factor = best

    chosen_parameters.append(
        (
            fold + 1,
            draw_factor,
            away_factor,
        )
    )

    for row in test:
        probs = adjust(
            row,
            draw_factor,
            away_factor,
        )

        calibrated_items.append(
            (
                row["actual"],
                probs,
            )
        )

        calibrated_rows.append({
            **row,
            "probs": probs,
        })

calibrated = metrics(calibrated_items)

# ============================================================
# OUTPUT
# ============================================================

print()
print("=" * 72)
print("GOALVDLINE - CROSS VALIDATED PROBABILITY CALIBRATION")
print("=" * 72)

print()
print("--- BASELINE ---")
print(
    f"Accuracy: {baseline['accuracy']*100:.1f}%"
)
print(
    f"Brier:    {baseline['brier']:.4f}"
)
print(
    f"Log Loss: {baseline['logloss']:.4f}"
)

print()
print("--- CALIBRATO CROSS-VALIDATED ---")
print(
    f"Accuracy: {calibrated['accuracy']*100:.1f}%"
)
print(
    f"Brier:    {calibrated['brier']:.4f}"
)
print(
    f"Log Loss: {calibrated['logloss']:.4f}"
)

print()
print("--- PARAMETRI SCELTI PER FOLD ---")

for fold, draw_factor, away_factor in chosen_parameters:
    print(
        f"Fold {fold}: "
        f"X x{draw_factor:.1f} | "
        f"2 x{away_factor:.1f}"
    )

baseline_predictions = Counter()

for row in rows:
    probs = raw_probs(row)
    prediction = max(probs, key=probs.get)
    baseline_predictions[prediction] += 1

calibrated_predictions = Counter()

for row in calibrated_rows:
    prediction = max(
        row["probs"],
        key=row["probs"].get,
    )

    calibrated_predictions[prediction] += 1

print()
print("--- DISTRIBUZIONE PRONOSTICI ---")

print(
    "Baseline: "
    f"1={baseline_predictions['1']} | "
    f"X={baseline_predictions['X']} | "
    f"2={baseline_predictions['2']}"
)

print(
    "Calibrata: "
    f"1={calibrated_predictions['1']} | "
    f"X={calibrated_predictions['X']} | "
    f"2={calibrated_predictions['2']}"
)

actual_counts = Counter(
    row["actual"]
    for row in rows
)

print(
    "Reale:    "
    f"1={actual_counts['1']} | "
    f"X={actual_counts['X']} | "
    f"2={actual_counts['2']}"
)

print()
print("--- PERFORMANCE PER ESITO CALIBRATO ---")

for outcome in ("1", "X", "2"):
    subset = []

    for row in calibrated_rows:
        predicted = max(
            row["probs"],
            key=row["probs"].get,
        )

        if predicted == outcome:
            subset.append(row)

    if not subset:
        print(f"{outcome}: nessun pronostico")
        continue

    hits = sum(
        1
        for row in subset
        if row["actual"] == outcome
    )

    print(
        f"{outcome}: "
        f"{hits}/{len(subset)} "
        f"({hits/len(subset)*100:.1f}%)"
    )

print()
print("--- CALIBRAZIONE PROBABILITÀ MASSIMA ---")

bins = [
    (0.30, 0.40),
    (0.40, 0.50),
    (0.50, 0.60),
    (0.60, 0.70),
    (0.70, 0.80),
    (0.80, 1.01),
]

for low, high in bins:
    subset = []

    for row in calibrated_rows:
        probs = row["probs"]

        predicted = max(
            probs,
            key=probs.get,
        )

        max_probability = probs[predicted]

        if low <= max_probability < high:
            subset.append(
                (
                    row,
                    predicted,
                    max_probability,
                )
            )

    if not subset:
        continue

    hits = sum(
        1
        for row, predicted, _ in subset
        if row["actual"] == predicted
    )

    avg_probability = (
        sum(p for _, _, p in subset)
        / len(subset)
    )

    print(
        f"{low*100:2.0f}-{high*100:2.0f}%: "
        f"n={len(subset):2d} | "
        f"prob media={avg_probability*100:5.1f}% | "
        f"reale={hits/len(subset)*100:5.1f}%"
    )

print()
print("=" * 72)
