#!/bin/sh
set -e

echo "========================================"
echo "SMARTBET - XCODE CLOUD SETUP"
echo "========================================"

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "Installazione Flutter..."

git clone https://github.com/flutter/flutter.git \
  --depth 1 \
  -b stable \
  "$HOME/flutter"

export FLUTTER_ROOT="$HOME/flutter"
export PATH="$FLUTTER_ROOT/bin:$PATH"

echo "Flutter:"
flutter --version

echo "Recupero dipendenze..."
flutter pub get

echo "========================================"
echo "SMARTBET - SETUP COMPLETATO"
echo "========================================"
