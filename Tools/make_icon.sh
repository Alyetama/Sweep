#!/usr/bin/env bash
#
# Generates Resources/AppIcon.icns from Tools/render_icon.swift.
#
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-Resources/AppIcon.icns}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift Tools/render_icon.swift "$TMP/icon_1024.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
	sips -z "$s" "$s" "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
	d=$((s * 2))
	sips -z "$d" "$d" "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "✓ Icon written to $OUT"
