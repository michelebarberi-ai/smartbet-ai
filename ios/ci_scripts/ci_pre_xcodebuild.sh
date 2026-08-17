#!/bin/sh
set -e

echo "========================================"
echo "SMARTBET - PRE XCODEBUILD"
echo "========================================"

cd "$CI_PRIMARY_REPOSITORY_PATH"

export FLUTTER_ROOT="$HOME/flutter"
export PATH="$FLUTTER_ROOT/bin:$PATH"

if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  echo "Installazione Flutter..."

  git clone \
    --depth 1 \
    --branch stable \
    https://github.com/flutter/flutter.git \
    "$FLUTTER_ROOT"
fi

echo "Flutter:"
"$FLUTTER_ROOT/bin/flutter" --version

echo "Recupero dipendenze..."
"$FLUTTER_ROOT/bin/flutter" pub get

echo "Preparazione configurazione iOS..."
"$FLUTTER_ROOT/bin/flutter" build ios --config-only --no-codesign

echo "========================================"
echo "SMARTBET - PRE XCODEBUILD COMPLETATO"
echo "========================================"
