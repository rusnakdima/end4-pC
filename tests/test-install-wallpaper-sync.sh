#!/usr/bin/env bash
# Contract test: the wallpaper-sync hook is portable and its "preserve existing
# script" branch actually compares two different paths.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
INSTALL="$ROOT/install.sh"

# 1. No self-comparison: the deployed path and the source must differ.
if grep -q 'sddm-wallpaper-sync.sh" != "$sync_dest"' "$INSTALL"; then
    fail 'preserve branch compares the destination with itself'
fi

# 2. No developer-specific home baked into the embedded hook.
if grep -q '/home/dmitriy' "$INSTALL"; then
    fail 'embedded wallpaper sync hardcodes a developer home'
fi

# 3. The hook derives the home from the resolved target.
grep -q 'TARGET_HOME' "$INSTALL" ||
    fail 'wallpaper sync does not use TARGET_HOME'

echo 'PASS: portable wallpaper sync hook contract'
