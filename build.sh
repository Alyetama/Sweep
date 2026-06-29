#!/usr/bin/env bash
#
# Builds Sweep and assembles a double-clickable .app bundle.
#
set -euo pipefail
cd "$(dirname "$0")"

APP="Sweep"
CONFIG="${1:-release}"
BUNDLE="$APP.app"

if [[ ! -f Resources/AppIcon.icns ]]; then
	echo "▸ Generating app icon…"
	./Tools/make_icon.sh Resources/AppIcon.icns || echo "  (icon generation skipped)"
fi

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/$APP"
if [[ ! -f "$BIN" ]]; then
	echo "✗ Build product not found at $BIN" >&2
	exit 1
fi

echo "▸ Assembling ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
cp Info.plist "$BUNDLE/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
	cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "▸ Code signing (ad-hoc)…"
codesign --force --sign - "$BUNDLE"

echo "✓ Built ./$BUNDLE"
