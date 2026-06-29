#!/usr/bin/env bash
#
# Build (release) and (re)launch Sweep.
#
set -euo pipefail
cd "$(dirname "$0")"

./build.sh release

echo "▸ Relaunching…"
killall Sweep >/dev/null 2>&1 || true
open ./Sweep.app

echo "✓ Sweep is running."
