#!/usr/bin/env bash
# Contract test: the themed WlSessionLock is the only lock client. A watchdog
# restarts the shell after a crash and clears Hyprland's crash screen only once
# the themed lock is secure again. No hyprlock bridge or fallback may remain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
GS="$ROOT/GlobalStates.qml"
LS="$ROOT/modules/common/panels/lock/LockScreen.qml"
CFG="$ROOT/modules/common/Config.qml"
GUARD="$ROOT/scripts/lock/end4pc-lock-guard"

body_of() {
    awk -v name="function $2(" '
        index($0, name) { found = 1 }
        found { print }
        found && /^    }/ { exit }
    ' "$1"
}

# 1. Runtime markers: lock state + reload state only.
grep -q 'readonly property string lockStatePath.*end4-pC-locked' "$GS" ||
    fail 'missing lock state marker path'
grep -q 'readonly property string reloadMarkerPath.*end4-pC-reloading' "$GS" ||
    fail 'missing reload marker path'

# 2. No hyprlock bridge API or marker survives anywhere in the lock code.
if grep -qE 'HyprlockBridge|bridgeMarker|hyprlock-bridge' "$GS" "$LS"; then
    fail 'hyprlock bridge API still present'
fi

# 3. Reload always writes its marker first and never starts a second lock.
reload_body="$(body_of "$GS" requestShellReload)"
[[ -n "$reload_body" ]] || fail 'requestShellReload() not found'
grep -q 'reloadMarkerFile.setText' <<<"$reload_body" ||
    fail 'reload does not write the reload marker'
grep -q 'Quickshell.reload(true)' <<<"$reload_body" ||
    fail 'reload no longer calls Quickshell.reload(true)'
marker_pos="$(grep -bo 'reloadMarkerFile.setText' <<<"$reload_body" | head -1 | cut -d: -f1)"
reload_pos="$(grep -bo 'Quickshell.reload(true)' <<<"$reload_body" | head -1 | cut -d: -f1)"
[[ "$marker_pos" -lt "$reload_pos" ]] || fail 'reload marker written too late'

# 4. Lock state is written before screenLocked flips, so a reload cannot lose it.
lock_body="$(body_of "$GS" lock)"
[[ -n "$lock_body" ]] || fail 'lock() not found'
write_pos="$(grep -bo 'writeLockState(true)' <<<"$lock_body" | head -1 | cut -d: -f1)"
locked_pos="$(grep -bo 'screenLocked = true' <<<"$lock_body" | head -1 | cut -d: -f1)"
[[ -n "$write_pos" && -n "$locked_pos" && "$write_pos" -lt "$locked_pos" ]] ||
    fail 'lock state written after screenLocked'

# 5. hyprlock stays an explicit opt-in, but is never a recovery client.
grep -q 'property bool useHyprlock: false' "$CFG" || fail 'useHyprlock default changed'
grep -q 'Config.options.lock.useHyprlock' <<<"$lock_body" || fail 'hyprlock opt-in branch removed'
grep -q 'Config.options.lock.useHyprlock' "$LS" || fail 'lock surface opt-in guard removed'

# 6. onSecureChanged only clears the startup flag; no bridge teardown.
secure_body="$(awk '/onSecureChanged: \{/{found=1} found{print} found && /^        \}/{exit}' "$LS")"
[[ -n "$secure_body" ]] || fail 'onSecureChanged handler not found'
grep -q 'lock.secure' <<<"$secure_body" || fail 'onSecureChanged is not guarded by lock.secure'
grep -q 'startupLockPending = false' <<<"$secure_body" ||
    fail 'secure lock does not clear startupLockPending'
if grep -q 'pkill\|hyprlock' <<<"$secure_body"; then
    fail 'secure path still manages a second lock client'
fi

# 7. IPC exposes the secure state the watchdog depends on.
grep -q '"locked-secure"' "$LS" || fail 'lock.status() has no secure state'
grep -q '"locked-insecure"' "$LS" || fail 'lock.status() has no insecure state'

# 8. The watchdog is theme-only: no hyprlock/fallback/bridge code at all.
if grep -qEi 'hyprlock|fallback|bridge|pkill' "$GUARD"; then
    fail 'watchdog still contains a secondary lock client or bridge logic'
fi
grep -q 'clear_crashed_lockscreen()' "$GUARD" ||
    fail 'watchdog does not clear the compositor crash screen'
grep -q 'HYPRLAND_INSTANCE_SIGNATURE' "$GUARD" ||
    fail 'watchdog does not use the live compositor instance'
grep -q 'RETRY_SECONDS' "$GUARD" ||
    fail 'watchdog has no retry after a failed restart'
grep -q 'XDG_STATE_HOME' "$GUARD" ||
    fail 'watchdog log is not in the user state dir'
if grep -q '/tmp/end4pc-lock-guard.log' "$GUARD"; then
    fail 'watchdog still logs to a root-owned /tmp path'
fi

echo 'PASS: theme-only lock contract'
