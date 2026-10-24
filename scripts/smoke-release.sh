#!/bin/bash
# Intended for disposable CI runners: never stop or replace an existing user app.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${CI:-}" = true ] || { echo 'Use only on disposable CI runners' >&2; exit 2; }
[ "$(uname -m)" = "$EXPECTED_ARCH" ]
(cd dist && shasum -a 256 -c SHA256SUMS)
version="$(bash scripts/check-release-version.sh)"
work="$(mktemp -d)"
pid=""
cleanup() { if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; rm -rf "$work"; }
trap cleanup EXIT
ditto -x -k "dist/ClipboardHistory-$version.zip" "$work/unzip"
app="$work/unzip/ClipboardHistory-$version/ClipboardHistory.app"
python3 scripts/verify-release-app.py "$app"
CLIPBOARD_HISTORY_DB="$work/history.db" "$app/Contents/MacOS/ClipboardHistory" > "$work/launch.log" 2>&1 &
pid=$!
sleep 8
kill -0 "$pid" || { cat "$work/launch.log"; exit 1; }
[ -s "$work/history.db" ]
echo "PASS: native $EXPECTED_ARCH package process survived startup"
