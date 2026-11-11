#!/usr/bin/env bash
#
# aic8800-check.sh — verify the AIC8800D80 USB WiFi+BT dongle stack.
#
# The Hotspot feature works on two hardware paths (see ./README.md):
#   A) onboard MT7922 (this repo's laptop): wlan0 does STA+AP, nothing AIC needed
#   B) AIC8800D80 USB dongle: dedicated radio, wlan0 + ap0 vif, self-managed regdb
#
# Run this AFTER plugging the dongle to see whether path B is ready.
# Read-only — safe to run any time, with or without the dongle present.
#
# Usage: ./aic8800-check.sh
# Exit:  0 = dongle stack ready (or dongle intentionally absent), 1 = problems
#
set -u

PASS=0; MISS=0; WARN=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; PASS=$((PASS+1)); }
miss() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; MISS=$((MISS+1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; WARN=$((WARN+1)); }
hint() { printf '         \033[2m-> %s\033[0m\n' "$*"; }

echo "== AIC8800 dongle stack check =="

# 1. is the dongle even plugged in? ------------------------------------------
DONGLE=""
if command -v lsusb &>/dev/null; then
    # Real AIC IDs: 368b:8d81 (operational) / a69c:5721 (mass-storage boot, needs modeswitch)
    DONGLE="$(lsusb 2>/dev/null | grep -iE '368b:|a69c:|0a69:' || true)"
fi
MTBT="$(lsusb 2>/dev/null | grep -i '13d3:3585' || true)"
if [ -z "$DONGLE" ]; then
    [ -n "$MTBT" ] && warn "13d3:3585 (MediaTek 'Wireless_Device') = BT half of the MT7922, not an AIC dongle"
    echo "-- AIC dongle NOT present (only needed for the dedicated-radio path) --"
    hint "onboard-wifi path (MT7922) needs none of this; see README §Hardware paths"
    hint "when you plug the dongle in: re-run this script"
    exit 0
fi
echo "found: $DONGLE"

# 2. kernel module ------------------------------------------------------------
if lsmod | grep -q '^aic8800_fdrv '; then
    ok "module aic8800_fdrv loaded"
else
    miss "module aic8800_fdrv not loaded"
    hint "modprobe aic8800_fdrv  (order matters: aic_load_fw BEFORE aic8800_fdrv)"
    hint "load order file: /etc/modules-load.d/aic8800.conf"
fi
if lsmod | grep -q '^aic_load_fw '; then ok "module aic_load_fw loaded"; else
    warn "aic_load_fw not loaded (needed to fetch firmware at plug-in)"
fi

# 3. DKMS build ---------------------------------------------------------------
if command -v dkms &>/dev/null && dkms status 2>/dev/null | grep -qi aic8800; then
    ok "dkms: $(dkms status 2>/dev/null | grep -i aic8800 | head -1)"
else
    miss "no aic8800 dkms build registered"
    hint "source lives in the dots-hyprland repo: dots-extra/aic8800-usb-*/ (see its INSTALL.md)"
    hint "kernel upgrades need the dkms module rebuilt for the new kernel"
fi

# 4. firmware -----------------------------------------------------------------
if [ -d /lib/firmware/aic8800D80 ] || [ -f /lib/firmware/aic8800_fw ]; then
    ok "firmware present: $(ls -d /lib/firmware/aic8800D80 /lib/firmware/aic8800_fw 2>/dev/null | tr '\n' ' ')"
else
    miss "AIC8800 firmware missing under /lib/firmware/"
    hint "firmware ships with the dkms source tree (see INSTALL.md)"
fi

# 5. modules-load at boot -----------------------------------------------------
MLD=/etc/modules-load.d/aic8800.conf
if [ -f "$MLD" ]; then
    ok "$MLD exists"
    # both loaders must be listed; explicit modinfo deps (aic8800_fdrv → aic_load_fw)
    # make the line order irrelevant — modprobe resolves them either way
    local_all=1
    grep -q '^aic_load_fw' "$MLD" || { local_all=0; warn "$MLD: missing aic_load_fw"; }
    grep -q '^aic8800_fdrv' "$MLD" || { local_all=0; warn "$MLD: missing aic8800_fdrv"; }
    [ "$local_all" = 1 ] && ok "both aic_load_fw and aic8800_fdrv listed (modprobe resolves order)"
else
    miss "$MLD missing"
    hint "create it with: aic_load_fw / aic8800_fdrv / btusb / aic_zlp_quirk (one per line)"
fi

# 6. udev binding -------------------------------------------------------------
if ls /etc/udev/rules.d/*aic* &>/dev/null; then
    ok "udev rules: $(ls /etc/udev/rules.d/*aic* | xargs -n1 basename | tr '\n' ' ')"
else
    warn "no /etc/udev/rules.d/*aic* rules"
    hint "usually optional (static modinfo aliases match 368b:8d81); if the dongle shows up"
    hint "but creates no wlan interface, copy the rules from archpc:/etc/udev/rules.d/"
fi

# 7. wifi interface actually created and bound? --------------------------------
BOUND=""
for n in /sys/class/net/*; do
    [ -e "$n/driver" ] || continue
    if readlink -f "$n/driver" 2>/dev/null | grep -q aic8800_fdrv; then
        BOUND="$(basename "$n")"
    fi
done
if [ -n "$BOUND" ]; then
    ok "wifi netdev '$BOUND' bound to aic8800_fdrv"
    if [ "$BOUND" = "wlan0" ]; then
        ok "it is wlan0 — the helper targets wlan0 verbatim (works as-is)"
    else
        warn "'$BOUND' != wlan0 — the helper hardcodes wlan0 (and the aic8800_fdrv check)"
        hint "either keep the dongle as wlan0 (unplug onboard wifi), or adapt AP_IFACE="
        hint "and the sta_freq() target in /usr/local/bin/aic-hotspot before using it"
    fi
else
    miss "no netdev bound to aic8800_fdrv"
    hint "check dmesg | tail -30 for firmware/USB errors after plug-in"
    hint "NEVER reload aic modules while in use — on this hardware it can brick the"
    hint "device until a full power cycle (helper deliberately never touches modules)"
fi

# 8. hotspot helper agrees? ---------------------------------------------------
if [ -x /usr/local/bin/aic-hotspot ]; then
    out="$(/usr/local/bin/aic-hotspot status 2>/dev/null || true)"
    if printf '%s' "$out" | grep -q '"active"'; then
        ok "helper status: $out"
    else
        warn "helper status returned nothing"
    fi
else
    miss "/usr/local/bin/aic-hotspot missing — run: sudo ./setup-hotspot.sh"
fi

echo
echo "== summary: $PASS pass, $MISS fail, $WARN warn =="
[ "$MISS" -eq 0 ] || exit 1
