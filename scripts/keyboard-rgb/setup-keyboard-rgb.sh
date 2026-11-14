#!/usr/bin/env bash
#
# setup-keyboard-rgb.sh — provision the system side of the end4-pC keyboard RGB
# feature.
#
# The theme's services/Brightness.qml talks ONLY to /usr/local/bin/kbd-rgb via
# `sudo -n` and parses one JSON line of output. This script installs every piece
# that contract needs, idempotently (safe to re-run):
#
#   1. helper     /usr/local/bin/kbd-rgb              (from ./kbd-rgb, byte-exact)
#   2. sudoers    /etc/sudoers.d/zz-kbd-rgb           NOPASSWD for the theme user
#   3. unit       /etc/systemd/system/kbd-rgb-restore.service  (colour at boot)
#   4. legacy     disables kbd-backlight-restore.service and points the old
#                 script path at the new helper
#   5. module     verifies qc71_laptop is loaded with debugregs=1, which is what
#                 exposes the raw EC RAM file the helper writes
#
# Usage:
#   sudo ./setup-keyboard-rgb.sh                 # install (user = $SUDO_USER)
#   sudo ./setup-keyboard-rgb.sh --user dmitriy  # theme user to grant NOPASSWD
#   ./setup-keyboard-rgb.sh --check              # verify (works unprivileged)
#   sudo ./setup-keyboard-rgb.sh --uninstall     # remove what this installed
#
# See ./README.md for the register map, why the obvious alternatives do not
# work on this machine, and troubleshooting.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SRC="$HERE/kbd-rgb"
HELPER_DST="/usr/local/bin/kbd-rgb"
SUDOERS="/etc/sudoers.d/zz-kbd-rgb"
UNIT="/etc/systemd/system/kbd-rgb-restore.service"
LEGACY_UNIT="/etc/systemd/system/kbd-backlight-restore.service"
LEGACY_SCRIPT="/usr/local/bin/kbd-backlight-restore.sh"
LEGACY_SHIM="$HERE/../kbd-backlight-restore.sh"
STATE_DIR="/var/lib/ambxst"
EC_FILE="/sys/kernel/debug/qc71_laptop/ec"

THEME_USER="${SUDO_USER:-dmitriy}"
MODE="install"
FAILS=0

log()  { printf '[kbd-rgb] %s\n' "$*"; }
fail() { printf '[kbd-rgb] FAIL: %s\n' "$*"; FAILS=$((FAILS+1)); }
ok()   { printf '[kbd-rgb] ok:   %s\n' "$*"; }
warn() { printf '[kbd-rgb] warn: %s\n' "$*"; }

usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        --user)      THEME_USER="${2:?--user needs a name}"; shift 2 ;;
        --check)     MODE="check"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        -h|--help)   usage ;;
        *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
done

need_root() {
    [ "$EUID" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
install_helper() {
    [ -f "$HELPER_SRC" ] || { echo "helper source missing: $HELPER_SRC" >&2; exit 1; }
    install -m 755 -o root -g root "$HELPER_SRC" "$HELPER_DST"
    cmp -s "$HELPER_SRC" "$HELPER_DST" && ok "helper installed: $HELPER_DST (byte-exact)" \
        || fail "helper mismatch after install"
}

install_sudoers() {
    # MUST sort last in /etc/sudoers.d: sudoers uses the LAST matching entry,
    # so an earlier "user ALL=(ALL) ALL" would otherwise override this tag.
    # The grant is scoped to one binary; the helper validates its own arguments
    # and is the only thing allowed to reach the EC file.
    cat > "$SUDOERS" <<EOF
# Managed by end4-pC scripts/keyboard-rgb/setup-keyboard-rgb.sh -- do not edit.
$THEME_USER ALL=(ALL) NOPASSWD: $HELPER_DST
EOF
    chmod 440 "$SUDOERS"
    visudo -cf "$SUDOERS" >/dev/null && ok "sudoers: $SUDOERS (visudo verified)" \
        || fail "visudo rejected $SUDOERS"
}

install_unit() {
    mkdir -p "$STATE_DIR"
    cat > "$UNIT" <<EOF
[Unit]
Description=Restore keyboard RGB colour
After=multi-user.target

[Service]
Type=oneshot
# Applies /var/lib/ambxst/kbd-rgb.state; with no state this prints
# {"restored":false,...} and exits 0, so a fresh machine always boots.
ExecStart=$HELPER_DST restore
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now kbd-rgb-restore.service >/dev/null 2>&1 \
        && ok "kbd-rgb-restore.service installed + enabled" \
        || fail "could not enable kbd-rgb-restore.service"
}

remove_legacy() {
    # The legacy service ran a script writing to /sys/class/leds/rgb:kbd_backlight,
    # a device this machine has never had, so it silently did nothing at every
    # boot. Leaving it enabled would make boot restore look like it already worked.
    if [ -f "$LEGACY_UNIT" ]; then
        systemctl disable --now kbd-backlight-restore.service >/dev/null 2>&1 || true
        rm -f "$LEGACY_UNIT"
        systemctl daemon-reload
        ok "removed legacy kbd-backlight-restore.service (dead sysfs path)"
    fi
    if [ -f "$LEGACY_SCRIPT" ]; then
        # Installed byte-exact from the repo so the two cannot drift apart again.
        if [ -f "$LEGACY_SHIM" ]; then
            install -m 755 -o root -g root "$LEGACY_SHIM" "$LEGACY_SCRIPT"
            ok "legacy kbd-backlight-restore.sh now delegates to $HELPER_DST"
        else
            warn "shim source missing: $LEGACY_SHIM (legacy script left untouched)"
        fi
    fi
}

# ---------------------------------------------------------------------------
# verification (shared by install and --check)
# ---------------------------------------------------------------------------
check_module() {
    if ! grep -q '^qc71_laptop ' /proc/modules 2>/dev/null; then
        fail "qc71_laptop not loaded (check /etc/modules-load.d/qc71-laptop.conf)"
        return
    fi
    ok "qc71_laptop loaded"
    if [ -r /sys/module/qc71_laptop/parameters/debugregs ]; then
        if [ "$(cat /sys/module/qc71_laptop/parameters/debugregs)" = "Y" ]; then
            ok "debugregs=1 (raw EC RAM exposed in debugfs)"
        else
            fail "debugregs is off: set 'options qc71_laptop debugregs=1' in /etc/modprobe.d/qc71_laptop.conf and reboot"
        fi
    fi
    if [ -e "$EC_FILE" ]; then
        ok "EC register file present: $EC_FILE"
        if [ -r "$EC_FILE" ]; then
            ok "EC register file readable"
        else
            fail "$EC_FILE is not readable as root"
        fi
    else
        fail "missing $EC_FILE — without it there is no path to the keyboard"
    fi
}

check_cmd() { # <label> <command...>
    local label="$1"; shift
    if "$@" &>/dev/null; then ok "$label"; else fail "$label"; fi
}

verify() {
    log "verifying..."
    check_cmd "helper present + executable" test -x "$HELPER_DST"
    if [ "$EUID" -eq 0 ]; then
        check_cmd "sudoers parses (visudo)"  visudo -cf "$SUDOERS"
    elif [ -f "$SUDOERS" ]; then
        ok "sudoers present: $SUDOERS (visudo check needs root)"
    else
        fail "sudoers missing: $SUDOERS"
    fi
    check_cmd "kbd-rgb-restore.service enabled" systemctl is-enabled kbd-rgb-restore.service
    if [ -f "$LEGACY_UNIT" ]; then
        fail "legacy kbd-backlight-restore.service is still installed"
    else
        ok "legacy restore service removed"
    fi
    check_module

    # Probe through the EXACT path Brightness.qml uses (sudo -n as theme user).
    local json="" via=""
    if [ "$EUID" -eq 0 ] && [ -n "$THEME_USER" ] && [ "$THEME_USER" != "root" ] \
    && id "$THEME_USER" &>/dev/null; then
        json="$(runuser -u "$THEME_USER" -- timeout 60 sudo -n "$HELPER_DST" probe 2>/dev/null || true)"
        via="sudo -n as $THEME_USER"
        [ -n "$json" ] || { json="$(timeout 60 "$HELPER_DST" probe 2>/dev/null || true)"; via="root direct"; }
    else
        json="$(timeout 60 sudo -n "$HELPER_DST" probe 2>/dev/null || true)"
        via="sudo -n as $(id -un)"
        [ -n "$json" ] || { json="$(timeout 60 "$HELPER_DST" probe 2>/dev/null || true)"; via="direct"; }
    fi
    if printf '%s' "$json" | grep -q '"available":true'; then
        ok "helper probe [$via]: $json"
    else
        fail "helper probe returned nothing usable [$via]: ${json:-<empty>}"
    fi
    if [ "$FAILS" -eq 0 ]; then log "all checks passed."; else log "$FAILS check(s) failed."; fi
    return 0
}

do_install() {
    need_root
    log "installing (theme user=$THEME_USER)"
    install_helper
    install_sudoers
    install_unit
    remove_legacy
    verify
}

do_uninstall() {
    need_root
    [ -x "$HELPER_DST" ] && "$HELPER_DST" save >/dev/null 2>&1 || true
    systemctl disable --now kbd-rgb-restore.service >/dev/null 2>&1 || true
    rm -f "$UNIT" "$SUDOERS" "$HELPER_DST"
    systemctl daemon-reload 2>/dev/null || true
    log "removed: helper, sudoers, kbd-rgb-restore.service"
    log "kept:    $STATE_DIR/kbd-rgb.state (your colour), the qc71_laptop module"
    log "note:    the legacy restore service stays removed"
}

case "$MODE" in
    install)   do_install ;;
    check)     verify ;;
    uninstall) do_uninstall ;;
esac
