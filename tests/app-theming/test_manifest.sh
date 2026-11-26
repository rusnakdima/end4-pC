#!/usr/bin/env bash
#
# Validate features/app-theming/manifest.json as the window-type catalog.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/features/app-theming/manifest.json"

pass=0
fail=0
check() {
    local name="$1" condition="$2"
    if eval "$condition"; then
        printf 'PASS %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$name"
        fail=$((fail + 1))
    fi
}

check 'manifest is valid JSON' \
    "jq -e . '$MANIFEST' >/dev/null 2>&1"
check 'manifest has no stale MaterialYou scheme names' \
    "! grep -q 'MaterialYou' '$MANIFEST'"

for id in gtk3 qtWidgets qtQuick; do
    check "catalog has $id entry" \
        "jq -e --arg id '$id' '.catalog[] | select(.id == \$id)' '$MANIFEST' >/dev/null 2>&1"
    for field in mechanism compatible patterns fallback; do
        check "catalog $id has non-empty $field" \
            "jq -e --arg id '$id' --arg field '$field' '.catalog[] | select(.id == \$id) | .[\$field] | select(type == \"array\" and length > 0 or type == \"string\" and length > 0)' '$MANIFEST' >/dev/null 2>&1"
    done
done

for sink in qt-quick theme-provision; do
    check "manifest reserves $sink sink" \
        "jq -e --arg id '$sink' '.sinks[] | select(.id == \$id)' '$MANIFEST' >/dev/null 2>&1"
done

printf '%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
