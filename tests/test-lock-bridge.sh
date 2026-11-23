#!/usr/bin/env bash
# Contract test: a lock/reload race is covered by hyprlock until the themed
# WlSessionLock reports secure, and the themed lock stays primary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
GS="$ROOT/GlobalStates.qml"
LS="$ROOT/modules/common/panels/lock/LockScreen.qml"
CFG="$ROOT/modules/common/Config.qml"

body_of() {
    awk -v name="function $2(" '
        index($0, name) { found = 1 }
        found { print }
        found && /^    }/ { exit }
    ' "$1"
}

# 1. Both runtime markers exist.
grep -q 'readonly property string reloadMarkerPath.*end4-pC-reloading' "$GS" ||
    fail 'missing reload marker path'
grep -q 'readonly property string bridgeMarkerPath.*end4-pC-hyprlock-bridge' "$GS" ||
    fail 'missing hyprlock bridge marker path'

# 2. A reload while locked starts the bridge before the engine is torn down.
reload_body="$(body_of "$GS" requestShellReload)"
[[ -n "$reload_body" ]] || fail 'requestShellReload() not found'
grep -q 'screenLocked' <<<"$reload_body" || fail 'reload does not check screenLocked'
grep -q 'startHyprlockBridge()' <<<"$reload_body" || fail 'reload does not start hyprlock bridge'
grep -q 'Quickshell.reload(true)' <<<"$reload_body" || fail 'reload no longer calls Quickshell.reload(true)'
start_pos="$(grep -bo 'startHyprlockBridge()' <<<"$reload_body" | head -1 | cut -d: -f1)"
reload_pos="$(grep -bo 'Quickshell.reload(true)' <<<"$reload_body" | head -1 | cut -d: -f1)"
[[ "$start_pos" -lt "$reload_pos" ]] || fail 'hyprlock bridge starts after the reload'

# 3. Locking while a reload is in progress also starts the bridge.
lock_body="$(body_of "$GS" lock)"
[[ -n "$lock_body" ]] || fail 'lock() not found'
grep -q 'reloadMarkerFile' <<<"$lock_body" || fail 'lock() does not inspect the reload marker'
grep -q 'startHyprlockBridge()' <<<"$lock_body" || fail 'lock() does not start hyprlock bridge'

# 4. The bridge is only torn down from the secure path; it never starts a lock.
end_body="$(body_of "$GS" endHyprlockBridge)"
[[ -n "$end_body" ]] || fail 'endHyprlockBridge() not found'
if grep -q 'pidof hyprlock' <<<"$end_body"; then
    fail 'endHyprlockBridge() must not start hyprlock'
fi
grep -q 'pkill' <<<"$end_body" || fail 'endHyprlockBridge() does not terminate hyprlock'

# 5. LockScreen dismisses the bridge only when the theme lock is secure.
secure_body="$(awk '/onSecureChanged: \{/{found=1} found{print} found && /^        \}/{exit}' "$LS")"
[[ -n "$secure_body" ]] || fail 'onSecureChanged handler not found'
grep -q 'lock.secure' <<<"$secure_body" || fail 'onSecureChanged is not guarded by lock.secure'
grep -q 'GlobalStates.endHyprlockBridge()' <<<"$secure_body" ||
    fail 'onSecureChanged does not hand back to the theme lock'

# 6. The themed lock remains the default.
grep -q 'property bool useHyprlock: false' "$CFG" || fail 'useHyprlock default changed'
grep -q 'Config.options.lock.useHyprlock' <<<"$lock_body" || fail 'hyprlock opt-in branch removed'

echo 'PASS: lock/reload bridge contract'
