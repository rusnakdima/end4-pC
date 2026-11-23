#!/usr/bin/env bash
# Regression tests for the BluetoothStatus fallback's action/availability wiring.
#
# Two bugs this pins down:
#   - two consecutive actions must be sent as ONE helper invocation; exec()
#     stops a running process, so separate setPower/startDiscovery calls cancel
#     each other, and an onExited re-query cancels the surviving action.
#   - the BT tile must remain visible when BlueZ is completely down (the
#     agreed tradeoff), i.e. availability cannot depend on a successful query.
#
# Run:  bash tests/test_bluetooth_qml_wiring.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS="$SCRIPT_DIR/services/BluetoothStatus.qml"
DIALOG="$SCRIPT_DIR/modules/ii/sidebarRight/SidebarRightContent.qml"
CONTROL="$SCRIPT_DIR/modules/waffle/actionCenter/bluetooth/BluetoothControl.qml"

fail=0
check() {
    local label="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file"; then
        printf '  OK   %s\n' "$label"
    else
        printf 'FAIL: %s (missing %q in %s)\n' "$label" "$pattern" "$file" >&2
        fail=1
    fi
}
check_absent() {
    local label="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file"; then
        printf 'FAIL: %s (unexpected %q in %s)\n' "$label" "$pattern" "$file" >&2
        fail=1
    else
        printf '  OK   %s\n' "$label"
    fi
}

check "single batched action entry point exists" "$STATUS" 'function runActions(actions)'
check "power+discover convenience exists" "$STATUS" 'function setPowerAndDiscover'
check_absent "no actionPending re-query race" "$STATUS" 'actionPending'
check "availability does not require a successful query" "$STATUS" 'quickshellLive || root.helperRan'
check "helper-run flag is set on parsed state" "$STATUS" 'root.helperRan = true'
check "right-panel dialog batches power+discovery" "$DIALOG" 'setPowerAndDiscover(true)'
check "action-center toggle batches power+discovery" "$CONTROL" 'setPowerAndDiscover(checked)'

exit "$fail"
