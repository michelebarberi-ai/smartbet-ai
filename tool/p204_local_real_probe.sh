#!/usr/bin/env bash
set -euo pipefail

# P20.4: real official Flutter engine on the local Mac.
# This script NEVER connects to the Render headless service or Neon.
# Real fixture/odds providers may be contacted in read-only fashion.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "$(git branch --show-current)" != "feature/b45-p20-4-multiday" ]]; then
  echo "P20.4 BLOCCATO: passa al branch feature/b45-p20-4-multiday"
  exit 2
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "P20.4 BLOCCATO: ci sono modifiche locali ai file tracciati"
  exit 2
fi
if ! command -v flutter >/dev/null || ! command -v python3 >/dev/null || ! command -v node >/dev/null; then
  echo "P20.4 BLOCCATO: servono Flutter, Python 3 e Node.js"
  exit 2
fi
if [[ ! -f test/engine/goalvdline_official_headless_worker_test.dart ]]; then
  echo "P20.4 BLOCCATO: test ufficiale Flutter mancante"
  exit 2
fi
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/goalvdline-p204-local.XXXXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
export GOALVDLINE_HEADLESS_RUN=1
export GOALVDLINE_HEADLESS_REVISION
GOALVDLINE_HEADLESS_REVISION="$(git rev-parse --verify HEAD)"
export GOALVDLINE_HEADLESS_RESULT_PATH="$TMP_DIR/result.json"

# Explicitly limit this probe to 3 events, 3 coupons, and 3 Rome calendar days.
export GOALVDLINE_HEADLESS_REQUEST_B64
GOALVDLINE_HEADLESS_REQUEST_B64="$(python3 - <<'PY'
import base64, datetime, json
from zoneinfo import ZoneInfo
instant = datetime.datetime.now(datetime.timezone.utc)
day = instant.astimezone(ZoneInfo('Europe/Rome')).date().isoformat()
body = {
    'protocol': 'goalvdline-official-coupon-v1',
    'dayKey': day,
    'generatedAfter': instant.isoformat(timespec='milliseconds').replace('+00:00', 'Z'),
    'preferences': {
        'requested': True,
        'hour': 8,
        'minute': 0,
        'events': 3,
        'minimumMarketProbability': 65,
        'market': 'MULTI',
        'notifyChanges': False,
        'systemMode': 'THREE_SAME_FIXTURES',
        'windowDays': 3,
    },
}
print(base64.b64encode(json.dumps(body, separators=(',', ':')).encode()).decode())
PY
)"
echo "========== P20.4 PROVA LOCALE UFFICIALE =========="
echo "Branch: $(git branch --show-current)"
echo "Commit: ${GOALVDLINE_HEADLESS_REVISION:0:12}"
echo "Motore Flutter reale, 3 schedine da 3 eventi, finestra di 3 giorni"
echo "Nessun token Render / nessuna connessione Neon"
echo
if ! flutter test --no-pub --reporter compact \
  test/engine/goalvdline_official_headless_worker_test.dart >"$TMP_DIR/flutter.log" 2>&1; then
  echo "P20.4 MOTORE: ERRORE FLUTTER (nessuna modifica a Render/Neon)"
  tail -n 16 "$TMP_DIR/flutter.log"
  exit 1
fi
if [[ ! -f "$GOALVDLINE_HEADLESS_RESULT_PATH" ]]; then
  echo "P20.4 MOTORE: file ufficiale mancante"
  exit 1
fi
node <<'NODE'
'use strict';
const fs = require('node:fs');
const {validateGeneratedCoupon, localClock, allowedRomeDays} =
  require('./backend/auto_coupon/daily_schedule');
const request = JSON.parse(Buffer.from(process.env.GOALVDLINE_HEADLESS_REQUEST_B64,
  'base64').toString('utf8'));
const output = JSON.parse(fs.readFileSync(process.env.GOALVDLINE_HEADLESS_RESULT_PATH,'utf8'));
if (output.protocol !== request.protocol || output.officialEngine !== true ||
    output.revision !== process.env.GOALVDLINE_HEADLESS_REVISION) {
  throw Error('P20.4: identita del motore non verificabile');
}
if (output.status === 'no_eligible_coupon' && output.coupon == null) {
  console.log('P20.4 MOTORE: NO_COUPON (nessuna schedina idonea anche su 3 giorni)');
  console.log('Il motore ha terminato correttamente; prova READY ancora da effettuare');
  process.exit(0);
}
if (output.status !== 'ready') throw Error('P20.4: stato ufficiale imprevisto');
const now = new Date();
const check = validateGeneratedCoupon({
  coupon: output.coupon, preferences:request.preferences, now,
});
if (!check.valid || check.dayKey !== request.dayKey) {
  throw Error('P20.4 CONTRATTO: NON VALIDO (' + check.reason + ')');
}
const allowed = allowedRomeDays(now,3);
const slip = output.coupon;
const dayCounts = Object.fromEntries([...allowed].map(key=>[key,0]));
for (const event of slip.events) {
  const day = localClock(new Date(event.kickoffAt)).dayKey;
  dayCounts[day] = (dayCounts[day] || 0) + 1;
}
console.log('P20.4 MOTORE: READY');
console.log('Varianti: '+slip.coupons.length+' (stesse '+slip.events.length+' partite)');
console.log('Giorni delle partite:', JSON.stringify(dayCounts));
console.log('Soglia probabilita: >=65%, quota reale: >=1.25 (verificate da Node)');
console.log('P20.4 VALIDAZIONE LOCALE: SUPERATA');
NODE
