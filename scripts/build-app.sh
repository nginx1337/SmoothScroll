#!/bin/bash
# Builds a release SmoothScroll.app into ./build and signs it locally.
#   scripts/build-app.sh            # ad-hoc signature
#   SIGN_ID="Developer ID Application: …" scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/SmoothScroll.app"
SIGN_ID="${SIGN_ID:--}"

scripts/test.sh
swift build -c release
BIN="$(swift build -c release --show-bin-path)/SmoothScroll"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SmoothScroll"
# Drop debug/local symbols: they embed absolute build paths (incl. the
# user's home folder name), which must not ship inside the app.
strip -S -x "$APP/Contents/MacOS/SmoothScroll"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # from scripts/make-icon.swift

# Hardened runtime, no entitlements: the app needs no network, files, camera, etc.
codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo
echo "Built $APP"
echo "Install: cp -R \"$APP\" /Applications/ && open /Applications/SmoothScroll.app"
