#!/usr/bin/env bash
# Wiring regressions for separate zram/swap resource reporting.
#
# Run:  bash tests/test_resource_zram.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$SCRIPT_DIR/services/ResourceUsage.qml"
BAR="$SCRIPT_DIR/modules/ii/bar/Resources.qml"
POPUP="$SCRIPT_DIR/modules/ii/bar/ResourcesPopup.qml"
OVERLAY="$SCRIPT_DIR/modules/ii/overlay/resources/Resources.qml"
CONFIG="$SCRIPT_DIR/modules/common/Config.qml"
BAR_CONFIG="$SCRIPT_DIR/modules/ii/settings/pages/BarConfig.qml"
QUICK="$SCRIPT_DIR/services/SettingsQuickControls.qml"

fail=0
check() {
    local label="$1" file="$2" pattern="$3"
    if grep -qF -- "$pattern" "$file"; then
        printf '  OK   %s\n' "$label"
    else
        printf 'FAIL: %s (missing %q in %s)\n' "$label" "$pattern" "$file" >&2
        fail=1
    fi
}
check_count() {
    local label="$1" file="$2" pattern="$3" minimum="$4" found
    found=$(grep -cF -- "$pattern" "$file" || true)
    if [ "$found" -ge "$minimum" ]; then
        printf '  OK   %s (%s occurrences)\n' "$label" "$found"
    else
        printf 'FAIL: %s (expected >=%s occurrences of %q in %s, got %s)\n' "$label" "$minimum" "$pattern" "$file" "$found" >&2
        fail=1
    fi
}

# --- service: detect zram from /proc/swaps ---------------------------------
check "service reads /proc/swaps" "$SERVICE" 'path: "/proc/swaps"'
check "zram total property" "$SERVICE" 'property real zramTotal'
check "zram free property" "$SERVICE" 'property real zramFree'
check "zram used derives from total-free" "$SERVICE" 'property real zramUsed: zramTotal - zramFree'
check "zram percentage property" "$SERVICE" 'property real zramUsedPercentage'
check "zram max string property" "$SERVICE" 'property string maxAvailableZramString'
check "zram history property" "$SERVICE" 'property list<real> zramUsageHistory'
check "zram history updater" "$SERVICE" 'function updateZramUsageHistory()'
check "swaps file reloaded on poll" "$SERVICE" 'fileSwaps.reload()'
check "zram device matched in /proc/swaps" "$SERVICE" '/dev/zram'
check "zram subtracted from meminfo swap total" "$SERVICE" 'memSwapTotal - zramTotal'
check "zram subtracted from meminfo swap used" "$SERVICE" 'memSwapFree) - zramUsed'
check "zram history sampled" "$SERVICE" 'updateZramUsageHistory()'

# --- bar: one ZRAM entry in each of the four layouts -----------------------
check_count "bar has four ZRAM entries" "$BAR" 'label: "ZRAM"' 4
check_count "bar reads zram percentage" "$BAR" 'ResourceUsage.zramUsedPercentage' 4
check_count "bar honours zram visibility toggle" "$BAR" 'Config.options.bar.resources.alwaysShowZram' 4
check_count "bar honours zram warning threshold" "$BAR" 'Config.options.bar.resources.zramWarningThreshold' 4

# --- popup and overlay -----------------------------------------------------
check "popup has a Zram card" "$POPUP" 'label: "Zram"'
check "popup card reads zram usage" "$POPUP" 'ResourceUsage.zramUsedPercentage'
check "popup card formats zram figures" "$POPUP" 'root.formatKB(ResourceUsage.zramUsed)'
check "overlay has a Zram tab" "$OVERLAY" 'Translation.tr("Zram")'
check "overlay tab reads zram history" "$OVERLAY" 'ResourceUsage.zramUsageHistory'
check "overlay tab reads zram max string" "$OVERLAY" 'ResourceUsage.maxAvailableZramString'

# --- config and settings surfaces ------------------------------------------
check "config has zram visibility default" "$CONFIG" 'property bool alwaysShowZram'
check "config has zram warning default" "$CONFIG" 'property int zramWarningThreshold'
check "settings has Zram toggle" "$BAR_CONFIG" 'Config.options.bar.resources.alwaysShowZram'
check "quick settings has Zram toggle" "$QUICK" '"bar:Zram": root.optionSwitch("bar.resources.alwaysShowZram")'

# --- live calculation basis (only on hosts with an active zram swap) -------
if [ -r /proc/swaps ] && awk '$1 ~ /^\/dev\/zram[0-9]+$/ {found=1} END {exit !found}' /proc/swaps; then
    zram_total=$(awk '$1 ~ /^\/dev\/zram[0-9]+$/ {sum += $3} END {print sum + 0}' /proc/swaps)
    mem_swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    if [ "$mem_swap_total" -ge "$zram_total" ]; then
        printf '  OK   host zram (%s kB) fits inside meminfo swap (%s kB)\n' "$zram_total" "$mem_swap_total"
    else
        printf 'FAIL: host zram (%s kB) exceeds meminfo swap (%s kB)\n' "$zram_total" "$mem_swap_total" >&2
        fail=1
    fi
else
    printf '  OK   host has no active zram swap; subtraction basis N/A\n'
fi

if [ "$fail" -eq 0 ]; then
    printf 'resource zram wiring: PASS\n'
else
    printf 'resource zram wiring: FAIL\n' >&2
fi
exit "$fail"
