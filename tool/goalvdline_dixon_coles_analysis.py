import csv
import math
from collections import Counter
from pathlib import Path

CSV_PATH = Path("tool/goalvdline_match_engine_backtest_results.csv")
MAX_GOALS = 14

rows = []

with CSV_PATH.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for row in reader:
        rows.append({
            "fixture_id": int(row["fixture_id"]),
            "match": row["match"],
            "actual": row["actual"],
            "lambda_home": float(row["expected_home_goals"]),
            "lambda_away": float(row["expected_away_goals"]),
            "engine_p1": float(row["p1"]),
            "engine_px": float(row["px"]),
            "engine_p2": float(row["p2"]),
            "actual_over25": row["actual_over25"].lower() == "true",
            "engine_over25": float(row["p_over25"]),
            "actual_goal": row["actual_goal"].lower() == "true",
            "engine_goal": float(row["p_goal"]),
        })

rows.sort(key=lambda r: r["fixture_id"])


def poisson_prob(k, lam):
    return math.exp(-lam) * (lam ** k) / math.factorial(k)


def dixon_coles_tau(home_goals, away_goals, lh, la, rho):
    if home_goals == 0 and away_goals == 0:
        return 1.0 - (lh * la * rho)

    if home_goals == 0 and away_goals == 1:
        return 1.0 + (lh * rho)

    if home_goals == 1 and away_goals == 0:
        return 1.0 + (la * rho)

    if home_goals == 1 and away_goals == 1:
        return 1.0 - rho

    return 1.0


def probabilities_from_lambdas(lh, la, rho=0.0):
    cells = []
    total_mass = 0.0

    for hg in range(MAX_GOALS + 1):
        ph = poisson_prob(hg, lh)

        for ag in range(MAX_GOALS + 1):
            pa = poisson_prob(ag, la)

            tau = dixon_coles_tau(
                hg,
                ag,
                lh,
                la,
                rho,
            )

            if tau <= 0:
                return None

            probability = ph * pa * tau

            cells.append((hg, ag, probability))
            total_mass += probability

    if total_mass <= 0:
        return None

    p1 = 0.0
    px = 0.0
    p2 = 0.0
    over25 = 0.0
    goal = 0.0

    for hg, ag, raw_probability in cells:
        p = raw_probability / total_mass

        if hg > ag:
            p1 += p
        elif hg == ag:
            px += p
        else:
            p2 += p

        if hg + ag >= 3:
            over25 += p

        if hg > 0 and ag > 0:
            goal += p

    return {
        "1": p1,
        "X": px,
        "2": p2,
        "over25": over25,
        "goal": goal,
    }


def metrics_1x2(items):
    correct = 0
    brier = 0.0
    logloss = 0.0

    for actual, probs in items:
        predicted = max(("1", "X", "2"), key=lambda x: probs[x])

        if predicted == actual:
            correct += 1

        for outcome in ("1", "X", "2"):
            target = 1.0 if outcome == actual else 0.0
            error = probs[outcome] - target
            brier += error * error

        actual_probability = max(probs[actual], 1e-12)
        logloss += -math.log(actual_probability)

    n = len(items)

    return {
        "accuracy": correct / n,
        "brier": brier / n,
        "logloss": logloss / n,
    }


def binary_metrics(items, probability_key, actual_key):
    hits = 0
    brier = 0.0

    for row, probs in items:
        probability = probs[probability_key]
        actual = row[actual_key]

        predicted = probability >= 0.5

        if predicted == actual:
            hits += 1

        target = 1.0 if actual else 0.0
        brier += (probability - target) ** 2

    n = len(items)

    return {
        "accuracy": hits / n,
        "brier": brier / n,
    }


# ============================================================
# MOTORE ATTUALE - MONTE CARLO
# ============================================================

engine_items = []

for row in rows:
    engine_items.append((
        row["actual"],
        {
            "1": row["engine_p1"],
            "X": row["engine_px"],
            "2": row["engine_p2"],
        },
    ))

engine_metrics = metrics_1x2(engine_items)

# ============================================================
# POISSON ANALITICA SENZA DIXON-COLES
# ============================================================

poisson_rows = []

for row in rows:
    probs = probabilities_from_lambdas(
        row["lambda_home"],
        row["lambda_away"],
        rho=0.0,
    )

    poisson_rows.append((row, probs))

poisson_metrics = metrics_1x2([
    (
        row["actual"],
        probs,
    )
    for row, probs in poisson_rows
])

# ============================================================
# 5-FOLD CROSS VALIDATION DI RHO
# ============================================================

fold_count = 5

# Range prudente.
# rho negativo aumenta soprattutto 0-0 e 1-1
# e riduce 1-0 / 0-1.
rho_values = [
    value / 100.0
    for value in range(-20, 6)
]

dc_test_rows = []
chosen_rhos = []

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

    for rho in rho_values:
        train_items = []
        valid = True

        for row in train:
            probs = probabilities_from_lambdas(
                row["lambda_home"],
                row["lambda_away"],
                rho=rho,
            )

            if probs is None:
                valid = False
                break

            train_items.append(
                (
                    row["actual"],
                    probs,
                )
            )

        if not valid:
            continue

        score = metrics_1x2(train_items)

        candidate = (
            score["logloss"],
            score["brier"],
            -score["accuracy"],
            abs(rho),
            rho,
        )

        if best is None or candidate < best:
            best = candidate

    if best is None:
        raise RuntimeError(
            f"Nessun rho valido per fold {fold + 1}"
        )

    rho = best[-1]

    chosen_rhos.append(rho)

    for row in test:
        probs = probabilities_from_lambdas(
            row["lambda_home"],
            row["lambda_away"],
            rho=rho,
        )

        dc_test_rows.append((row, probs))

dc_metrics = metrics_1x2([
    (
        row["actual"],
        probs,
    )
    for row, probs in dc_test_rows
])

# ============================================================
# OVER / UNDER E GOAL
# ============================================================

poisson_over = binary_metrics(
    poisson_rows,
    "over25",
    "actual_over25",
)

poisson_goal = binary_metrics(
    poisson_rows,
    "goal",
    "actual_goal",
)

dc_over = binary_metrics(
    dc_test_rows,
    "over25",
    "actual_over25",
)

dc_goal = binary_metrics(
    dc_test_rows,
    "goal",
    "actual_goal",
)

engine_over_items = []

engine_goal_hits = 0
engine_goal_brier = 0.0
engine_over_hits = 0
engine_over_brier = 0.0

for row in rows:
    over_prediction = row["engine_over25"] >= 0.5
    goal_prediction = row["engine_goal"] >= 0.5

    if over_prediction == row["actual_over25"]:
        engine_over_hits += 1

    if goal_prediction == row["actual_goal"]:
        engine_goal_hits += 1

    engine_over_brier += (
        row["engine_over25"] -
        (1.0 if row["actual_over25"] else 0.0)
    ) ** 2

    engine_goal_brier += (
        row["engine_goal"] -
        (1.0 if row["actual_goal"] else 0.0)
    ) ** 2

engine_over = {
    "accuracy": engine_over_hits / len(rows),
    "brier": engine_over_brier / len(rows),
}

engine_goal = {
    "accuracy": engine_goal_hits / len(rows),
    "brier": engine_goal_brier / len(rows),
}

# ============================================================
# DISTRIBUZIONE PRONOSTICI
# ============================================================

def prediction_counts(items):
    counts = Counter()

    for row, probs in items:
        predicted = max(
            ("1", "X", "2"),
            key=lambda x: probs[x],
        )

        counts[predicted] += 1

    return counts


poisson_counts = prediction_counts(poisson_rows)
dc_counts = prediction_counts(dc_test_rows)

engine_counts = Counter()

for row in rows:
    probs = {
        "1": row["engine_p1"],
        "X": row["engine_px"],
        "2": row["engine_p2"],
    }

    engine_counts[
        max(("1", "X", "2"), key=lambda x: probs[x])
    ] += 1

actual_counts = Counter(row["actual"] for row in rows)

# ============================================================
# PROBABILITÀ MEDIA DEL PAREGGIO
# ============================================================

engine_avg_draw = sum(
    row["engine_px"]
    for row in rows
) / len(rows)

poisson_avg_draw = sum(
    probs["X"]
    for _, probs in poisson_rows
) / len(rows)

dc_avg_draw = sum(
    probs["X"]
    for _, probs in dc_test_rows
) / len(rows)

# ============================================================
# OUTPUT
# ============================================================

print()
print("=" * 76)
print("GOALVDLINE - DIXON COLES CROSS-VALIDATED ANALYSIS")
print("=" * 76)
print(f"Partite: {len(rows)}")

print()
print("--- RHO SCELTO IN OGNI FOLD ---")

for index, rho in enumerate(chosen_rhos, start=1):
    print(f"Fold {index}: rho = {rho:+.2f}")

print()
print(
    "Rho medio: "
    f"{sum(chosen_rhos) / len(chosen_rhos):+.3f}"
)

print()
print("--- 1X2 ---")

print(
    "Motore Monte Carlo: "
    f"accuracy {engine_metrics['accuracy']*100:5.1f}% | "
    f"Brier {engine_metrics['brier']:.4f} | "
    f"LogLoss {engine_metrics['logloss']:.4f}"
)

print(
    "Poisson analitica:   "
    f"accuracy {poisson_metrics['accuracy']*100:5.1f}% | "
    f"Brier {poisson_metrics['brier']:.4f} | "
    f"LogLoss {poisson_metrics['logloss']:.4f}"
)

print(
    "Dixon-Coles CV:      "
    f"accuracy {dc_metrics['accuracy']*100:5.1f}% | "
    f"Brier {dc_metrics['brier']:.4f} | "
    f"LogLoss {dc_metrics['logloss']:.4f}"
)

print()
print("--- DISTRIBUZIONE ESITO PRINCIPALE ---")

print(
    "Reale:        "
    f"1={actual_counts['1']:2d} | "
    f"X={actual_counts['X']:2d} | "
    f"2={actual_counts['2']:2d}"
)

print(
    "Monte Carlo:  "
    f"1={engine_counts['1']:2d} | "
    f"X={engine_counts['X']:2d} | "
    f"2={engine_counts['2']:2d}"
)

print(
    "Poisson:      "
    f"1={poisson_counts['1']:2d} | "
    f"X={poisson_counts['X']:2d} | "
    f"2={poisson_counts['2']:2d}"
)

print(
    "Dixon-Coles:  "
    f"1={dc_counts['1']:2d} | "
    f"X={dc_counts['X']:2d} | "
    f"2={dc_counts['2']:2d}"
)

print()
print("--- PROBABILITÀ MEDIA X ---")

print(f"Monte Carlo: {engine_avg_draw*100:.1f}%")
print(f"Poisson:     {poisson_avg_draw*100:.1f}%")
print(f"Dixon-Coles: {dc_avg_draw*100:.1f}%")
print(
    f"X reali:     "
    f"{actual_counts['X']/len(rows)*100:.1f}%"
)

print()
print("--- OVER / UNDER 2.5 ---")

print(
    "Monte Carlo: "
    f"accuracy {engine_over['accuracy']*100:5.1f}% | "
    f"Brier {engine_over['brier']:.4f}"
)

print(
    "Poisson:     "
    f"accuracy {poisson_over['accuracy']*100:5.1f}% | "
    f"Brier {poisson_over['brier']:.4f}"
)

print(
    "Dixon-Coles: "
    f"accuracy {dc_over['accuracy']*100:5.1f}% | "
    f"Brier {dc_over['brier']:.4f}"
)

print()
print("--- GOAL / NO GOAL ---")

print(
    "Monte Carlo: "
    f"accuracy {engine_goal['accuracy']*100:5.1f}% | "
    f"Brier {engine_goal['brier']:.4f}"
)

print(
    "Poisson:     "
    f"accuracy {poisson_goal['accuracy']*100:5.1f}% | "
    f"Brier {poisson_goal['brier']:.4f}"
)

print(
    "Dixon-Coles: "
    f"accuracy {dc_goal['accuracy']*100:5.1f}% | "
    f"Brier {dc_goal['brier']:.4f}"
)

print()
print("=" * 76)
