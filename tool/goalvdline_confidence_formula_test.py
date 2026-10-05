import csv
from pathlib import Path

path = Path("tool/goalvdline_match_engine_backtest_results.csv")

rows = []

with path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for row in reader:
        probabilities = sorted(
            [
                float(row["p1"]),
                float(row["px"]),
                float(row["p2"]),
            ],
            reverse=True,
        )

        best = probabilities[0]
        second = probabilities[1]

        best_clarity = max(
            0.0,
            min(
                1.0,
                (best - (1.0 / 3.0)) / (2.0 / 3.0),
            ),
        )

        separation_clarity = max(
            0.0,
            min(
                1.0,
                (best - second) / 0.40,
            ),
        )

        rows.append({
            "hit": row["hit"].lower() == "true",
            "data": int(row["data_confidence"]) / 100.0,
            "best": best_clarity,
            "separation": separation_clarity,
        })


def auc(values):
    positive = [score for score, hit in values if hit]
    negative = [score for score, hit in values if not hit]

    if not positive or not negative:
        return 0.0

    wins = 0.0
    comparisons = 0

    for p in positive:
        for n in negative:
            comparisons += 1

            if p > n:
                wins += 1.0
            elif p == n:
                wins += 0.5

    return wins / comparisons


def score_current(row):
    # Formula effettiva attuale:
    # 55% data
    # 27% best probability clarity
    # 18% separation clarity
    return (
        row["data"] * 0.55
        + row["best"] * 0.27
        + row["separation"] * 0.18
    )


def score_balanced(row):
    return (
        row["data"] * 0.35
        + row["best"] * 0.25
        + row["separation"] * 0.40
    )


def score_margin_heavy(row):
    return (
        row["data"] * 0.25
        + row["best"] * 0.20
        + row["separation"] * 0.55
    )


def score_guarded(row):
    # La qualità dati resta una protezione.
    #
    # La chiarezza dell'esito genera la maggior parte del punteggio,
    # ma dati scarsi possono abbassare il risultato finale.
    clarity = (
        row["best"] * 0.35
        + row["separation"] * 0.65
    )

    data_guard = 0.70 + (row["data"] * 0.30)

    return clarity * data_guard


formulas = {
    "ATTUALE": score_current,
    "BILANCIATA": score_balanced,
    "MARGIN HEAVY": score_margin_heavy,
    "DATA GUARD": score_guarded,
}

print()
print("=" * 76)
print("GOALVDLINE - CONFRONTO FORMULE CONFIDENCE")
print("=" * 76)

for name, formula in formulas.items():
    scored = [
        (
            formula(row),
            row["hit"],
        )
        for row in rows
    ]

    scored.sort(
        key=lambda item: item[0],
        reverse=True,
    )

    correct_scores = [
        score
        for score, hit in scored
        if hit
    ]

    wrong_scores = [
        score
        for score, hit in scored
        if not hit
    ]

    avg_correct = sum(correct_scores) / len(correct_scores)
    avg_wrong = sum(wrong_scores) / len(wrong_scores)

    print()
    print(f"--- {name} ---")

    print(
        f"AUC ranking: {auc(scored):.3f}"
    )

    print(
        f"Score medio corrette:  "
        f"{avg_correct*100:.1f}"
    )

    print(
        f"Score medio sbagliate: "
        f"{avg_wrong*100:.1f}"
    )

    print(
        f"Delta:                 "
        f"{(avg_correct-avg_wrong)*100:+.1f}"
    )

    for top in (5, 10, 15, 20, 25):
        subset = scored[:top]
        hits = sum(hit for _, hit in subset)

        print(
            f"Top {top:2d}: "
            f"{hits}/{len(subset)} "
            f"({hits/len(subset)*100:.1f}%)"
        )

print()
print("=" * 76)
