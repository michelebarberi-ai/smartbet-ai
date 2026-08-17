#!/bin/sh
set -e

echo "========================================"
echo "SMARTBET - XCODE CLOUD SETUP"
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

echo "Disabilitazione Swift Package Manager..."
"$FLUTTER_ROOT/bin/flutter" config --no-enable-swift-package-manager

echo "Recupero dipendenze Flutter..."
"$FLUTTER_ROOT/bin/flutter" pub get

echo "Installazione CocoaPods..."
cd ios
pod install
cd ..

echo "========================================"
echo "SMARTBET - SETUP COMPLETATO"
echo "========================================"
