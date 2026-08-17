#!/bin/sh
set -e

echo "========================================"
echo "SMARTBET - XCODE CLOUD POST CLONE"
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

echo "Generazione package Swift Flutter..."
"$FLUTTER_ROOT/bin/flutter" build ios --config-only --no-codesign

echo "Verifica package generato..."
test -f ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift

echo "========================================"
echo "SMARTBET - POST CLONE COMPLETATO"
echo "========================================"
