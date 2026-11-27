#!/usr/bin/env bash
# Contract test: live shell reloads go through the safe IPC helper, and both
# install.sh and sync.sh use it. Killing the shell would take the session down.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
HELPER="$ROOT/scripts/hyprland/reload-shell.sh"

# 1. A dedicated helper exists and is executable.
[[ -x "$HELPER" ]] || fail 'scripts/hyprland/reload-shell.sh is missing or not executable'

# 2. It reloads via the wallpapers IPC bridge with an explicit display, and
#    never kills the running shell.
grep -q 'wallpapers reloadShell' "$HELPER" ||
    fail 'helper does not call the wallpapers reloadShell IPC method'
grep -q 'WAYLAND_DISPLAY' "$HELPER" ||
    fail 'helper does not set WAYLAND_DISPLAY for the IPC call'
if grep -Eq 'killall|pkill[[:space:]]+(-x[[:space:]]+)?qs' "$HELPER"; then
    fail 'helper kills quickshell instead of using IPC'
fi

# 3. It refuses to touch a locked session.
grep -q 'lock status' "$HELPER" ||
    fail 'helper does not check the lock state before reloading'

# 4. Both callers delegate to it.
grep -q 'reload-shell.sh' "$ROOT/install.sh" ||
    fail 'install.sh does not reload the shell through the helper'
grep -q 'reload-shell.sh' "$ROOT/sync.sh" ||
    fail 'sync.sh does not reload the shell through the helper'

# 5. Callers honour --no-reload.
grep -q -- '--no-reload' "$ROOT/install.sh" ||
    fail 'install.sh has no --no-reload flag'
grep -q 'do_reload' "$ROOT/sync.sh" ||
    fail 'sync.sh does not gate the reload on do_reload'

echo 'PASS: safe shell reload contract'
