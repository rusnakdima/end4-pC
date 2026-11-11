#!/usr/bin/env bash
#
# setup-hotspot.sh — provision the system side of the end4-pC Hotspot (AP) feature.
#
# The theme's services/Hotspot.qml talks ONLY to /usr/local/bin/aic-hotspot via
# `sudo -n` and parses one JSON line of output. This script installs every piece
# that contract needs, idempotently (safe to re-run; never touches a live AP or
# restarts NetworkManager):
#
#   1. packages        hostapd dnsmasq iw python iptables networkmanager wireless-regdb
#   2. helper          /usr/local/bin/aic-hotspot            (from ./aic-hotspot, byte-exact)
#   3. sudoers         /etc/sudoers.d/zz-aic-hotspot        NOPASSWD for the theme user
#   4. NetworkManager  /etc/NetworkManager/conf.d/20-unmanaged-aic-ap.conf  (ap0 unmanaged)
#   5. ip_forward      /etc/sysctl.d/99-hotspot-forward.conf
#   6. regdomain       /etc/systemd/system/regdom.service   `iw reg set <CC>` at boot
#   7. unit hygiene    hostapd/dnsmasq systemd units disabled (helper runs its own instances)
#
# Usage:
#   sudo ./setup-hotspot.sh                  # install (default regdom KZ, user = $SUDO_USER)
#   sudo ./setup-hotspot.sh --regdom US      # different regulatory country
#   sudo ./setup-hotspot.sh --user dmitriy   # theme user to grant NOPASSWD
#   ./setup-hotspot.sh --check               # verify everything (works unprivileged)
#   sudo ./setup-hotspot.sh --uninstall      # remove everything this script installed
#
# See ./README.md for the full guide (hardware paths, troubleshooting, contract).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SRC="$HERE/aic-hotspot"
HELPER_DST="/usr/local/bin/aic-hotspot"
SUDOERS="/etc/sudoers.d/zz-aic-hotspot"
NM_CONF="/etc/NetworkManager/conf.d/20-unmanaged-aic-ap.conf"
REGDOM_UNIT="/etc/systemd/system/regdom.service"
SYSCTL_FILE="/etc/sysctl.d/99-hotspot-forward.conf"

REGDOM="KZ"                 # KZ = Asia/Almaty (this machine's jurisdiction)
THEME_USER="${SUDO_USER:-dmitriy}"
MODE="install"
FAILS=0

log()  { printf '[hotspot] %s\n' "$*"; }
fail() { printf '[hotspot] FAIL: %s\n' "$*"; FAILS=$((FAILS+1)); }
ok()   { printf '[hotspot] ok:   %s\n' "$*"; }
warn() { printf '[hotspot] warn: %s\n' "$*"; }

usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        --regdom)   REGDOM="${2:?--regdom needs a country code}"; shift 2 ;;
        --user)     THEME_USER="${2:?--user needs a name}"; shift 2 ;;
        --check)    MODE="check"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        -h|--help)  usage ;;
        *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
done
REGDOM="$(printf '%s' "$REGDOM" | tr '[:lower:]' '[:upper:]')"

need_root() {
    [ "$EUID" -eq 0 ] || { echo "run as root: sudo $0 ${*:-}" >&2; exit 1; }
}

current_reg() { iw reg get 2>/dev/null | sed -n '2s/^country \([A-Z0-9]*\).*/\1/p'; }

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
do_install() {
    need_root
    log "installing (regdom=$REGDOM, theme user=$THEME_USER)"

    # 1. packages (pacman only — this bundle targets Arch) ------------------
    local pkgs=(hostapd dnsmasq iw python iptables networkmanager wireless-regdb)
    local missing=()
    for p in "${pkgs[@]}"; do pacman -Q "$p" &>/dev/null || missing+=("$p"); done
    if [ "${#missing[@]}" -gt 0 ]; then
        log "installing packages: ${missing[*]}"
        pacman -S --noconfirm "${missing[@]}" || {
            echo "package install failed (offline?). Install manually: pacman -S ${missing[*]}" >&2
            exit 1
        }
    else
        ok "all packages present (${pkgs[*]})"
    fi

    # 2. helper --------------------------------------------------------------
    [ -f "$HELPER_SRC" ] || { echo "helper source missing: $HELPER_SRC" >&2; exit 1; }
    install -m 755 -o root -g root "$HELPER_SRC" "$HELPER_DST"
    cmp -s "$HELPER_SRC" "$HELPER_DST" && ok "helper installed: $HELPER_DST (byte-exact)" \
        || fail "helper mismatch after install"

    # 3. sudoers -------------------------------------------------------------
    cat > "$SUDOERS" <<EOF
# Managed by end4-pC scripts/hotspot/setup-hotspot.sh — do not edit by hand.
# MUST sort last in /etc/sudoers.d: sudoers uses the LAST matching entry, and
# an earlier "user ALL=(ALL) ALL" (password required) would otherwise override
# this NOPASSWD tag for the helper command.
$THEME_USER ALL=(ALL) NOPASSWD: $HELPER_DST
EOF
    chmod 440 "$SUDOERS"
    visudo -cf "$SUDOERS" >/dev/null && ok "sudoers: $SUDOERS (visudo verified)" \
        || fail "visudo rejected $SUDOERS"

    # 4. NetworkManager: ap0 must never be managed --------------------------
    mkdir -p /etc/NetworkManager/conf.d
    printf '[keyfile]\nunmanaged-devices=interface-name:ap0\n' > "$NM_CONF"
    chmod 644 "$NM_CONF"
    nmcli general reload >/dev/null 2>&1 || true
    ok "NetworkManager ap0-unmanaged rule: $NM_CONF"

    # 5. IPv4 forwarding (MASQUERADE source NAT needs it) -------------------
    if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
        echo "net.ipv4.ip_forward=1" > "$SYSCTL_FILE"
        sysctl -w net.ipv4.ip_forward=1 >/dev/null
        ok "ip_forward enabled ($SYSCTL_FILE)"
    else
        ok "ip_forward already = 1"
    fi

    # 6. boot-time regulatory domain ----------------------------------------
    # Without a valid regulatory country, 5 GHz AP channels are NO-IR and
    # hostapd refuses to beacon ("Frequency 5180 not allowed for AP mode").
    cat > "$REGDOM_UNIT" <<EOF
[Unit]
Description=Set wireless regulatory domain ($REGDOM)
After=systemd-modules-load.service
Before=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for i in \$(seq 1 15); do /usr/bin/iw reg set $REGDOM && exit 0; sleep 1; done; exit 1'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable regdom.service >/dev/null 2>&1
    iw reg set "$REGDOM" 2>/dev/null || true
    sleep 1
    local now; now="$(current_reg)"
    if [ "$now" = "$REGDOM" ]; then
        ok "regulatory domain: country $now (applied live + enabled at boot)"
    else
        warn "regulatory domain is '${now:-?}' — hint not applied yet."
        warn "cfg80211 caches a failed regulatory.db load until reboot; REBOOT once."
        warn "regdom.service applies '$REGDOM' automatically at every boot."
    fi

    # 7. hostapd/dnsmasq system units must stay off (helper runs private ones)
    local u
    for u in hostapd dnsmasq; do
        if systemctl is-enabled "$u.service" &>/dev/null; then
            systemctl disable --now "$u.service" >/dev/null 2>&1 || true
            ok "disabled system $u.service (helper runs its own instance)"
        fi
    done

    verify
}

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
    need_root
    [ -x "$HELPER_DST" ] && { "$HELPER_DST" stop >/dev/null 2>&1 || true; log "AP stopped if it was running"; }
    rm -f "$HELPER_DST" "$SUDOERS" "$NM_CONF" "$REGDOM_UNIT"
    systemctl daemon-reload 2>/dev/null || true
    nmcli general reload >/dev/null 2>&1 || true
    log "removed: helper, sudoers, NM conf, regdom.service"
    log "kept: wireless-regdb (harmless), $SYSCTL_FILE (harmless), ufw rules if any"
    log "note: a running AP was stopped; nothing else touched."
}

# ---------------------------------------------------------------------------
# shared verification (used by install and --check)
# ---------------------------------------------------------------------------
check_cmd() { # <label> <command...>
    local label="$1"; shift
    if "$@" &>/dev/null; then ok "$label"; else fail "$label"; fi
}

verify() {
    log "verifying..."
    check_cmd "helper present + executable"   test -x "$HELPER_DST"
    if [ "$EUID" -eq 0 ]; then
        check_cmd "sudoers parses (visudo)"   visudo -cf "$SUDOERS"
    elif [ -f "$SUDOERS" ]; then
        ok "sudoers present: $SUDOERS (visudo check needs root)"
    else
        fail "sudoers missing: $SUDOERS"
    fi
    check_cmd "NM conf present"               test -f "$NM_CONF"
    check_cmd "regdom.service enabled"        systemctl is-enabled regdom.service
    check_cmd "regulatory.db installed"       test -f /lib/firmware/regulatory.db
    check_cmd "ip_forward=1"                  test "$(sysctl -n net.ipv4.ip_forward)" = "1"

    # helper status through the EXACT path Hotspot.qml uses (sudo -n as theme user)
    local json="" via=""
    if [ "$EUID" -eq 0 ]; then
        if [ -n "$THEME_USER" ] && [ "$THEME_USER" != "root" ] && id "$THEME_USER" &>/dev/null; then
            json="$(runuser -u "$THEME_USER" -- sudo -n "$HELPER_DST" status 2>/dev/null || true)"
            via="sudo -n as $THEME_USER"
        fi
        if [ -z "$json" ]; then
            json="$("$HELPER_DST" status 2>/dev/null || true)"
            via="root direct"
            [ -n "$json" ] && warn "sudo -n path failed for '${THEME_USER:-?}'; root path works"
        fi
    else
        # we ARE the theme user here — this is literally the theme's command
        json="$(sudo -n "$HELPER_DST" status 2>/dev/null || true)"
        via="sudo -n as $(id -un)"
        if [ -z "$json" ]; then
            json="$("$HELPER_DST" status 2>/dev/null || true)"
            via="direct without sudo"
            [ -n "$json" ] && warn "sudo -n failed for $(id -un); only direct invocation works"
        fi
    fi
    if printf '%s' "$json" | grep -q '"active"'; then
        ok "helper status [$via]: $json"
    else
        fail "helper status returned nothing"
    fi

    local reg; reg="$(current_reg)"
    if [ "$reg" = "$REGDOM" ]; then ok "regulatory domain: $reg"; else
        if [ "$MODE" = "check" ]; then fail "regulatory domain is '${reg:-?}', want $REGDOM (reboot once if regdb was just installed)"; else
            warn "regulatory domain: ${reg:-?} (reboot once to apply $REGDOM)"
        fi
    fi

    if [ "$FAILS" -eq 0 ]; then log "ALL CHECKS PASSED"; else log "$FAILS CHECK(S) FAILED"; fi
    [ "$FAILS" -eq 0 ]
}

# ---------------------------------------------------------------------------
do_check() {
    # unprivileged-friendly: everything except visudo-readable bits works as user
    verify || true
    [ "$FAILS" -eq 0 ]
}

case "$MODE" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    check)     do_check ;;
esac
