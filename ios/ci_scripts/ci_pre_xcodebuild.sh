#!/bin/sh
set -e

echo "========================================"
echo "SMARTBET - PRE XCODEBUILD"
echo "========================================"

cd "$CI_PRIMARY_REPOSITORY_PATH"

export FLUTTER_ROOT="$HOME/flutter"
export PATH="$FLUTTER_ROOT/bin:$PATH"

rm -rf "$FLUTTER_ROOT"

echo "Installazione Flutter..."
git clone \
  --depth 1 \
  --branch stable \
  https://github.com/flutter/flutter.git \
  "$FLUTTER_ROOT"

echo "Flutter:"
"$FLUTTER_ROOT/bin/flutter" --version

echo "Disabilitazione Swift Package Manager..."
"$FLUTTER_ROOT/bin/flutter" config --no-enable-swift-package-manager

echo "Precache iOS..."
"$FLUTTER_ROOT/bin/flutter" precache --ios

echo "Flutter pub get..."
"$FLUTTER_ROOT/bin/flutter" pub get

echo "CocoaPods..."
cd ios
pod install
cd ..

echo "========================================"
echo "SMARTBET - PRE XCODEBUILD COMPLETATO"
echo "========================================"
