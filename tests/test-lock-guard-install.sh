#!/usr/bin/env bash
# Contract test: the lock watchdog is actually deployed and enabled. Without
# this, the guard code exists in the checkout but never runs on a live session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
UNIT="$ROOT/systemd/user/end4pc-lock-guard.service"
INSTALL="$ROOT/install.sh"
SYNC="$ROOT/sync.sh"

# 1. The unit must work for any target user, not just the developer's home.
grep -q 'ExecStart=%h/.local/bin/end4pc-lock-guard' "$UNIT" ||
    fail 'unit ExecStart is not portable (%h)'
if grep -q '/home/dmitriy' "$UNIT"; then
    fail 'unit still hardcodes a developer home'
fi
grep -q 'Restart=always' "$UNIT" || fail 'unit does not restart the watchdog'
if grep -q 'WAYLAND_DISPLAY=wayland-1' "$UNIT"; then
    fail 'unit hardcodes a stale Wayland display'
fi

# 2. install.sh deploys the script, the unit, and the enable symlink.
grep -q 'bin_dir=.*\.local/bin"' "$INSTALL" &&
    grep -q 'install -Dm755.*end4pc-lock-guard' "$INSTALL" ||
    fail 'installer does not deploy the guard script'
grep -q 'end4pc-lock-guard.service' "$INSTALL" ||
    fail 'installer does not deploy the guard unit'
grep -q 'default.target.wants' "$INSTALL" ||
    fail 'installer does not enable the guard unit'

# 3. sync.sh does the same, and only when not in dry-run mode.
grep -q '\.local/bin/end4pc-lock-guard' "$SYNC" ||
    fail 'sync does not deploy the guard script'
grep -q 'end4pc-lock-guard.service' "$SYNC" ||
    fail 'sync does not deploy the guard unit'
grep -q 'default.target.wants' "$SYNC" ||
    fail 'sync does not enable the guard unit'
if grep -n 'end4pc-lock-guard' "$SYNC" | grep -q '^' && ! grep -q 'dry_run -eq 0' "$SYNC"; then
    fail 'sync writes the guard outside its dry-run guard'
fi

echo 'PASS: lock watchdog deployment contract'
