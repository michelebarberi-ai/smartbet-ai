#!/usr/bin/env python3

import argparse
import csv
import json
import re
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

SOURCE = (
    ROOT
    / "tool"
    / "goalvdline_draw_suitability_backtest.dart"
)

DATA_DIR = ROOT / "tool" / "backtest_data"

MIN3_FILE = DATA_DIR / "draw_v3_validation2_min3.csv"
MIN10_FILE = DATA_DIR / "draw_v3_validation2_min10.csv"
MANIFEST_FILE = DATA_DIR / "draw_v3_validation2_manifest.csv"

START_DATE = date(2026, 10, 6)
PER_DATE = 25
MINIMA = (3, 10)


# ============================================================
# SOURCE PATCHING
# ============================================================

DATE_PATTERN = re.compile(
    r"final date = DateTime\("
    r"\s*\d{4}\s*,\s*\d+\s*,\s*\d+\s*"
    r"\);"
)

TAKE_PATTERN = re.compile(
    r"final selected = candidates"
    r"\.take\(\d+\)\.toList\(\);"
)

MIN_PATTERN = re.compile(
    r"backtestCurrentSeasonMinMatches:"
    r"\s*\d+\s*,"
)


def build_source(
    original: str,
    target: date,
    minimum: int,
) -> str:
    if not DATE_PATTERN.search(original):
        raise RuntimeError(
            "Pattern data non trovato nel backtest."
        )

    if not TAKE_PATTERN.search(original):
        raise RuntimeError(
            "Pattern candidates.take(...) non trovato."
        )

    if not MIN_PATTERN.search(original):
        raise RuntimeError(
            "Parametro backtestCurrentSeasonMinMatches "
            "non trovato."
        )

    code = DATE_PATTERN.sub(
        (
            "final date = DateTime("
            f"{target.year}, "
            f"{target.month}, "
            f"{target.day}"
            ");"
        ),
        original,
        count=1,
    )

    code = TAKE_PATTERN.sub(
        (
            "final selected = candidates"
            f".take({PER_DATE}).toList();"
        ),
        code,
        count=1,
    )

    code = MIN_PATTERN.sub(
        (
            "backtestCurrentSeasonMinMatches: "
            f"{minimum},"
        ),
        code,
        count=1,
    )

    return code


# ============================================================
# CSV DATASETS
# ============================================================

def read_rows(path: Path):
    if not path.exists():
        return []

    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def save_rows(path: Path, rows):
    if not rows:
        return

    rows.sort(
        key=lambda r: (
            r["datasetDate"],
            int(float(r["fixtureId"])),
        )
    )

    keys = list(rows[0].keys())

    for key in [
        "datasetDate",
        "resolverMin",
    ]:
        if key in keys:
            keys.remove(key)

    fieldnames = [
        "datasetDate",
        "resolverMin",
    ] + keys

    with path.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=fieldnames,
            extrasaction="ignore",
        )

        writer.writeheader()
        writer.writerows(rows)


# ============================================================
# MANIFEST
# ============================================================

MANIFEST_FIELDS = [
    "datasetDate",
    "resolverMin",
    "status",
    "candidates",
    "features",
]


def read_manifest():
    if not MANIFEST_FILE.exists():
        return []

    with MANIFEST_FILE.open(newline="") as f:
        return list(csv.DictReader(f))


def save_manifest(rows):
    rows.sort(
        key=lambda r: (
            r["datasetDate"],
            int(r["resolverMin"]),
        )
    )

    with MANIFEST_FILE.open(
        "w",
        newline="",
    ) as f:
        writer = csv.DictWriter(
            f,
            fieldnames=MANIFEST_FIELDS,
        )

        writer.writeheader()
        writer.writerows(rows)


def manifest_entry(
    manifest,
    target_text,
    minimum,
):
    for row in manifest:
        if (
            row["datasetDate"] == target_text
            and int(row["resolverMin"]) == minimum
        ):
            return row

    return None


# ============================================================
# SINGLE MIN RUN
# ============================================================

def collect_variant(
    *,
    original,
    target,
    minimum,
):
    target_text = target.isoformat()

    output_file = (
        MIN3_FILE
        if minimum == 3
        else MIN10_FILE
    )

    rows = read_rows(output_file)

    existing_for_date = [
        row
        for row in rows
        if row["datasetDate"] == target_text
    ]

    manifest = read_manifest()

    previous = manifest_entry(
        manifest,
        target_text,
        minimum,
    )

    if previous is not None:
        print(
            f"MIN{minimum}: già processata "
            f"({previous['status']}, "
            f"{previous['features']} feature)"
        )
        return True

    if existing_for_date:
        print(
            f"MIN{minimum}: dataset contiene già "
            f"{len(existing_for_date)} feature "
            "ma manca il manifest."
        )
        print(
            "Interrompo per evitare una modifica "
            "non verificata del dataset."
        )
        return False

    code = build_source(
        original,
        target,
        minimum,
    )

    temp = (
        ROOT
        / "tool"
        / (
            ".tmp_validation2_"
            f"min{minimum}_"
            f"{target:%Y%m%d}.dart"
        )
    )

    temp.write_text(code)

    try:
        process = subprocess.run(
            [
                "dart",
                "run",
                str(temp),
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

        output = process.stdout

    finally:
        if temp.exists():
            temp.unlink()

    if process.returncode != 0:
        failure_log = Path(
            "/tmp/"
            f"draw_v3_validation2_"
            f"min{minimum}_"
            f"{target:%Y%m%d}_ERROR.log"
        )

        failure_log.write_text(output)

        print(
            f"MIN{minimum}: ERRORE TECNICO "
            f"(exit={process.returncode})"
        )

        print(
            "Log diagnostico: "
            f"{failure_log}"
        )

        return False

    candidate_match = re.search(
        r"Partite selezionate:\s*(\d+)",
        output,
    )

    candidate_count = (
        int(candidate_match.group(1))
        if candidate_match
        else 0
    )

    feature_lines = [
        line
        for line in output.splitlines()
        if line.startswith("FEATURE_JSON ")
    ]

    # --------------------------------------------------------
    # ZERO CANDIDATI: RISULTATO VALIDO DEL COLLECTOR
    # --------------------------------------------------------

    if (
        not feature_lines
        and "Nessuna partita valida trovata."
        in output
    ):
        manifest.append(
            {
                "datasetDate": target_text,
                "resolverMin": str(minimum),
                "status": "ZERO_CANDIDATES",
                "candidates": "0",
                "features": "0",
            }
        )

        save_manifest(manifest)

        print(
            f"MIN{minimum}: OK - "
            "0 candidati validi"
        )

        return True

    # --------------------------------------------------------
    # CANDIDATI MA NESSUNA FEATURE:
    # NON LO CONSIDERIAMO SILENZIOSAMENTE VALIDO
    # --------------------------------------------------------

    if not feature_lines:
        review_log = Path(
            "/tmp/"
            f"draw_v3_validation2_"
            f"min{minimum}_"
            f"{target:%Y%m%d}_REVIEW.log"
        )

        review_log.write_text(output)

        print(
            f"MIN{minimum}: ATTENZIONE - "
            f"{candidate_count} candidati, "
            "0 FEATURE_JSON."
        )

        print(
            "La data NON viene marcata "
            "come completata."
        )

        print(
            "Log diagnostico: "
            f"{review_log}"
        )

        return False

    # --------------------------------------------------------
    # FEATURE
    # --------------------------------------------------------

    known_ids = {
        int(float(row["fixtureId"]))
        for row in rows
    }

    added = 0

    for line in feature_lines:
        payload = line[
            len("FEATURE_JSON "):
        ]

        data = json.loads(payload)

        fixture_id = int(
            float(data["fixtureId"])
        )

        if fixture_id in known_ids:
            continue

        known_ids.add(fixture_id)

        data["datasetDate"] = target_text
        data["resolverMin"] = minimum

        rows.append(data)
        added += 1

    save_rows(
        output_file,
        rows,
    )

    status = (
        "OK_FEATURES"
        if candidate_count == 0
        or len(feature_lines) == candidate_count
        else "OK_PARTIAL_FEATURES"
    )

    manifest.append(
        {
            "datasetDate": target_text,
            "resolverMin": str(minimum),
            "status": status,
            "candidates": str(candidate_count),
            "features": str(len(feature_lines)),
        }
    )

    save_manifest(manifest)

    print(
        f"MIN{minimum}: OK - "
        f"{len(feature_lines)} feature"
    )

    if (
        candidate_count
        and candidate_count
        != len(feature_lines)
    ):
        print(
            f"  candidati={candidate_count}, "
            f"feature={len(feature_lines)}"
        )

    return True


# ============================================================
# SAFE SUMMARY — NESSUNA PERFORMANCE
# ============================================================

def print_safe_summary():
    rows3 = read_rows(MIN3_FILE)
    rows10 = read_rows(MIN10_FILE)

    ids3 = {
        int(float(row["fixtureId"]))
        for row in rows3
    }

    ids10 = {
        int(float(row["fixtureId"]))
        for row in rows10
    }

    common = ids3 & ids10

    manifest = read_manifest()

    completed_dates = {
        row["datasetDate"]
        for row in manifest
    }

    print()
    print("=" * 72)
    print("VALIDATION 2 - SAFE COLLECTION SUMMARY")
    print("=" * 72)

    print(
        f"Date registrate: "
        f"{len(completed_dates)}"
    )

    print(
        f"Fixture MIN3:     "
        f"{len(ids3)}"
    )

    print(
        f"Fixture MIN10:    "
        f"{len(ids10)}"
    )

    print(
        f"Fixture comuni:   "
        f"{len(common)}"
    )

    if ids3 or ids10:
        union = ids3 | ids10

        coverage = (
            len(common)
            / len(union)
            * 100.0
        )

        print(
            f"Copertura comune: "
            f"{coverage:.1f}%"
        )

    print()
    print(
        "Performance predittive NON calcolate "
        "(anti-peeking)."
    )

    if len(common) < 50:
        print(
            f"Mancano almeno "
            f"{50-len(common)} fixture comuni "
            "al target minimo."
        )
    elif len(common) < 100:
        print(
            "Target minimo di 50 raggiunto."
        )
        print(
            f"Mancano {100-len(common)} "
            "fixture comuni al target preferibile."
        )
    else:
        print(
            "Target preferibile di "
            "100 fixture comuni raggiunto."
        )
        print(
            "Il collector NON apre "
            "automaticamente la valutazione."
        )

    print("=" * 72)


# ============================================================
# MAIN
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Collector prospettico GoalVdLine "
            "Draw V3 Validation 2."
        )
    )

    parser.add_argument(
        "date",
        help="Data da raccogliere: YYYY-MM-DD",
    )

    args = parser.parse_args()

    try:
        target = datetime.strptime(
            args.date,
            "%Y-%m-%d",
        ).date()

    except ValueError:
        raise SystemExit(
            "Formato data non valido. "
            "Usare YYYY-MM-DD."
        )

    if target < START_DATE:
        raise SystemExit(
            "Data vietata: Validation 2 parte "
            "dal 2026-10-06."
        )

    today = date.today()

    if target >= today:
        raise SystemExit(
            "Raccolta vietata per oggi o date future. "
            "Raccogliere solo giornate già concluse."
        )

    original = SOURCE.read_text()

    print("=" * 72)
    print("GOALVDLINE DRAW V3 - VALIDATION 2")
    print("=" * 72)
    print(f"Data: {target.isoformat()}")
    print(f"Massimo candidati: {PER_DATE}")
    print("Modalità: prospettica / anti-peeking")
    print("=" * 72)

    ok3 = collect_variant(
        original=original,
        target=target,
        minimum=3,
    )

    if not ok3:
        raise SystemExit(
            "MIN3 non completata. "
            "MIN10 non eseguita."
        )

    ok10 = collect_variant(
        original=original,
        target=target,
        minimum=10,
    )

    if not ok10:
        raise SystemExit(
            "MIN10 non completata."
        )

    print_safe_summary()


if __name__ == "__main__":
    main()
