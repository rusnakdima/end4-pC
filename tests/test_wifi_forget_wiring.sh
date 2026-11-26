#!/usr/bin/env bash
# Regression tests for the WiFi quick-panel forget / connect-disconnect wiring.
#
# Pins down:
#   - saved profiles are matched by TYPE 802-11-wireless (not "wifi");
#   - SSIDs reach nmcli as argv elements, never shell-interpolated;
#   - saved state refreshes after an action and on nmcli monitor updates;
#   - a row click expands (BT-style) instead of connecting directly.
#
# Run:  bash tests/test_wifi_forget_wiring.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORK="$SCRIPT_DIR/services/Network.qml"
ITEM="$SCRIPT_DIR/modules/ii/sidebarRight/wifiNetworks/WifiNetworkItem.qml"

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

check "saved profile filter uses NM wireless type" "$NETWORK" '802-11-wireless'
check "saved SSID predicate exists" "$NETWORK" 'function isWifiSaved'
check "forget action exists" "$NETWORK" 'function forgetWifiNetwork'
check "forget passes SSID as argv element" "$NETWORK" '"connection", "delete", ssid'
check "saved profiles refresh hook exists" "$NETWORK" 'getSavedWifiProfiles.running = true'
check "wifi row expands on click" "$ITEM" 'onClicked: expanded = !expanded'
check "forget button label" "$ITEM" 'Translation.tr("Forget")'
check "disconnect button label" "$ITEM" 'Translation.tr("Disconnect")'
check_absent "no direct connect on row click" "$ITEM" 'onClicked: Network.connectToWifiNetwork'

exit "$fail"
