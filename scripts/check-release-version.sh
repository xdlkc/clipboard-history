#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
if [ -n "${RELEASE_TAG:-}" ]; then
  [ "$RELEASE_TAG" = "v$version" ] || { echo "Tag $RELEASE_TAG does not match v$version" >&2; exit 1; }
fi
printf '%s\n' "$version"
