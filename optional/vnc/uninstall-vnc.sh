#!/usr/bin/env bash
#
# uninstall-vnc.sh — remove the optional end4-pC VNC/audio setup.
set -euo pipefail

MOD_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
log()  { echo "[vnc] $*"; }
warn() { echo "[vnc] WARN: $*" >&2; }

if [[ -n "${TARGET_HOME:-}" && -n "${TARGET_USER:-}" ]]; then
    :
elif [[ $(id -u) -eq 0 && -n "${SUDO_USER:-}" ]]; then
    TARGET_USER="$SUDO_USER"
    TARGET_HOME=$(eval echo "~$SUDO_USER")
else
    TARGET_USER=$(id -un)
    TARGET_HOME="$HOME"
fi
if [[ -n "${VNC_USER:-}" ]]; then
    TARGET_USER="$VNC_USER"
    TARGET_HOME=$(eval echo "~$TARGET_USER")
fi
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GROUP=$(id -gn "$TARGET_USER")

if [[ $(id -u) -eq 0 ]]; then ROOT=""; else ROOT="sudo"; fi
run_as_target() {
    local rt="/run/user/$TARGET_UID"
    if [[ $(id -u) -eq "$TARGET_UID" ]]; then
        env XDG_RUNTIME_DIR="$rt" DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus" "$@"
    elif [[ $(id -u) -eq 0 ]]; then
        runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="$rt" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus" "$@"
    else
        sudo -u "$TARGET_USER" env XDG_RUNTIME_DIR="$rt" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus" "$@"
    fi
}

CONFIG="${VNC_CONFIG:-$TARGET_HOME/.config/end4-pC/vnc.conf}"
if [[ -f "$CONFIG" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$CONFIG"
    set +a
fi
VNC_MODE="${VNC_MODE:-full}"
VNC_MIRROR_PORT="${VNC_MIRROR_PORT:-5901}"
VNC_HIDDEN_PORT="${VNC_HIDDEN_PORT:-5902}"
BACKUP=/var/lib/end4-pC-vnc/backup

restore_backup() {
    local f="$1" key
    key=$(printf '%s' "$f" | tr '/' '_')
    if [[ -e "$BACKUP/$key" ]]; then
        $ROOT cp -a "$BACKUP/$key" "$f"
        log "restored $f"
        return 0
    fi
    return 1
}

log "stopping VNC units"
run_as_target systemctl --user disable --now \
    wayvnc-mirror.service wayvnc-remote.service vnc-theme-hooks.service sunshine-remote.service \
    2>/dev/null || true
$ROOT systemctl disable --now hyprland-hidden.service 2>/dev/null || true

restore_backup /etc/environment || {
    if [[ -f /etc/environment ]]; then
        $ROOT sed -i '/^AQ_DRM_DEVICES=/d; /^LIBSEAT_BACKEND=/d' /etc/environment
    fi
}
restore_backup /etc/sddm.conf.d/10-autologin.conf || $ROOT rm -f /etc/sddm.conf.d/10-autologin.conf
restore_backup /etc/X11/xorg.conf.d/99-physical-only.conf || $ROOT rm -f /etc/X11/xorg.conf.d/99-physical-only.conf
restore_backup /etc/X11/xorg.conf.d/99-intel-only.conf || $ROOT rm -f /etc/X11/xorg.conf.d/99-intel-only.conf
restore_backup "$TARGET_HOME/.config/hypr/remote.lua" || rm -f "$TARGET_HOME/.config/hypr/remote.lua"

$ROOT rm -f \
    /etc/systemd/system/hyprland-hidden.service \
    /usr/local/bin/hyprland-hidden-run \
    /usr/local/bin/hyprland-hidden-start \
    /etc/modules-load.d/vkms.conf \
    /etc/udev/rules.d/99-vkms.rules

rm -f \
    "$TARGET_HOME/.config/wayvnc/mirror.conf" \
    "$TARGET_HOME/.config/wayvnc/remote.conf" \
    "$TARGET_HOME/.config/systemd/user/wayvnc-mirror.service" \
    "$TARGET_HOME/.config/systemd/user/wayvnc-remote.service" \
    "$TARGET_HOME/.config/systemd/user/vnc-theme-hooks.service" \
    "$TARGET_HOME/.config/systemd/user/sunshine-remote.service" \
    "$TARGET_HOME/.config/hypr/custom/scripts/vnc-theme-hooks.sh" \
    "$TARGET_HOME/.config/hypr/custom/scripts/vnc-theme-watch" \
    "$TARGET_HOME/.config/sunshine/sunshine-remote.conf" \
    "$TARGET_HOME/.config/pipewire/pipewire.conf.d/50-hypr-remote.conf"

$ROOT rm -rf "$TARGET_HOME/.config/hypr/custom/scripts/vnc-physical"
$ROOT udevadm control --reload 2>/dev/null || true
$ROOT systemctl daemon-reload
run_as_target systemctl --user daemon-reload 2>/dev/null || true

if [[ -e /var/lib/end4-pC-vnc/seatd-was-enabled ]]; then
    $ROOT systemctl enable --now seatd.service 2>/dev/null || warn "could not re-enable seatd"
    $ROOT rm -f /var/lib/end4-pC-vnc/seatd-was-enabled
fi

warn "UFW rules were not removed automatically; review ports $VNC_MIRROR_PORT, $VNC_HIDDEN_PORT and Sunshine ports."
log "removed the generated VNC files; reboot to return the display manager to its previous state."
