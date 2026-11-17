#!/usr/bin/env bash
#
# install-vnc.sh — optional VNC/remote-desktop setup for end4-pC.
#
# Installs the archpc-style layout:
#   :5901 physical Hyprland mirror (interactive, all physical outputs)
#   :5902 separate hidden Hyprland on VKMS
#   optional Sunshine/Moonlight audio
#
# Invoked by install.sh with --with-vnc, or run standalone.
set -euo pipefail

MOD_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FILES="$MOD_DIR/files"

log()  { echo "[vnc] $*"; }
warn() { echo "[vnc] WARN: $*" >&2; }
die()  { echo "[vnc] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Target user (same rules as install.sh: sudo -> SUDO_USER)
# ---------------------------------------------------------------------------
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

if [[ $(id -u) -eq 0 ]]; then
    ROOT=""
else
    ROOT="sudo"
fi

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

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG="${VNC_CONFIG:-$TARGET_HOME/.config/end4-pC/vnc.conf}"
if [[ -f "$CONFIG" ]]; then
    log "loading $CONFIG"
    set -a
    # shellcheck disable=SC1090
    . "$CONFIG"
    set +a
fi

VNC_MIRROR_PORT="${VNC_MIRROR_PORT:-5901}"
VNC_HIDDEN_PORT="${VNC_HIDDEN_PORT:-5902}"
VNC_AUDIO="${VNC_AUDIO:-sunshine}"
VNC_AUTOLOGIN="${VNC_AUTOLOGIN:-1}"
VNC_THEME_LOCK="${VNC_THEME_LOCK:-1}"
VNC_HIDDEN_OUTPUT="${VNC_HIDDEN_OUTPUT:-Virtual-1}"

if [[ -z "${VNC_BIND_ADDR:-}" ]]; then
    if command -v tailscale >/dev/null 2>&1; then
        VNC_BIND_ADDR=$(tailscale ip -4 2>/dev/null | head -n1 || true)
    fi
fi
if [[ -z "${VNC_BIND_ADDR:-}" ]]; then
    VNC_BIND_ADDR=127.0.0.1
    warn "no Tailscale IPv4 found; VNC will bind to 127.0.0.1 only"
fi
[[ "$VNC_AUDIO" == "sunshine" || "$VNC_AUDIO" == "none" ]] || {
    warn "unknown VNC_AUDIO='$VNC_AUDIO'; using none"
    VNC_AUDIO=none
}

RUNTIME="/run/user/$TARGET_UID"
HIDDEN_RUNTIME="$RUNTIME/remote"
BACKUP=/var/lib/end4-pC-vnc/backup

# ---------------------------------------------------------------------------
# Dependencies and GPU discovery
# ---------------------------------------------------------------------------
command -v pacman >/dev/null 2>&1 || die "pacman is required"

missing=()
for cmd in wayvnc jq grim hyprlock; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
command -v seatd >/dev/null 2>&1 || missing+=(seatd)
if [[ "$VNC_AUDIO" == sunshine ]] && ! command -v sunshine >/dev/null 2>&1; then
    missing+=(sunshine)
fi
if ((${#missing[@]})); then
    log "installing: ${missing[*]}"
    $ROOT pacman -S --needed --noconfirm "${missing[@]}" || warn "package install incomplete"
fi

if ! lsmod | grep -q '^vkms'; then
    log "loading vkms"
    $ROOT modprobe vkms || die "cannot load vkms"
fi
udevadm settle 2>/dev/null || true
VKMS_DEV=$(readlink -f /dev/dri/vkms 2>/dev/null || true)
[[ -n "$VKMS_DEV" ]] || VKMS_DEV=/dev/dri/card0
[[ -e "$VKMS_DEV" ]] || die "VKMS DRM node not found"

PHYS_CARD=""
for c in /dev/dri/card*; do
    [[ "$(readlink -f "$c")" == "$(readlink -f "$VKMS_DEV")" ]] && continue
    PHYS_CARD="$c"
    break
done
[[ -n "$PHYS_CARD" ]] || die "physical DRM card not found"
RENDER_DEV=$(ls /dev/dri/renderD* 2>/dev/null | head -n1 || true)
[[ -n "$RENDER_DEV" ]] || die "DRM render node not found"

log "VKMS=$VKMS_DEV physical=$PHYS_CARD render=$RENDER_DEV"
log "bind=$VNC_BIND_ADDR mirror=$VNC_MIRROR_PORT hidden=$VNC_HIDDEN_PORT audio=$VNC_AUDIO"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
$ROOT install -d -m 755 "$BACKUP"

backup_file() {
    local f="$1" key
    [[ -e "$f" ]] || return 0
    key=$(printf '%s' "$f" | tr '/' '_')
    $ROOT cp -a "$f" "$BACKUP/$key"
}

restore_backup() {
    local f="$1" key
    key=$(printf '%s' "$f" | tr '/' '_')
    if [[ -e "$BACKUP/$key" ]]; then
        $ROOT cp -a "$BACKUP/$key" "$f"
        return 0
    fi
    return 1
}

render() {
    local src="$1" dst="$2"
    sed \
        -e "s|@USER@|$TARGET_USER|g" \
        -e "s|@GROUP@|$TARGET_GROUP|g" \
        -e "s|@HOME@|$TARGET_HOME|g" \
        -e "s|@RUNTIME@|$RUNTIME|g" \
        -e "s|@BIND@|$VNC_BIND_ADDR|g" \
        -e "s|@VKMS@|$VKMS_DEV|g" \
        -e "s|@PHYS@|$PHYS_CARD|g" \
        -e "s|@RENDER@|$RENDER_DEV|g" \
        -e "s|@MIRROR_PORT@|$VNC_MIRROR_PORT|g" \
        -e "s|@HIDDEN_PORT@|$VNC_HIDDEN_PORT|g" \
        -e "s|VNC_THEME_LOCK=1|VNC_THEME_LOCK=$VNC_THEME_LOCK|g" \
        "$src" > "$dst"
}

install_rendered() {
    local src="$1" dst="$2" mode="$3" owner="${4:-root}"
    local tmp
    tmp=$(mktemp)
    render "$src" "$tmp"
    if [[ "$owner" == "user" ]]; then
        $ROOT install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$(dirname "$dst")"
        $ROOT install -m "$mode" -o "$TARGET_USER" -g "$TARGET_GROUP" "$tmp" "$dst"
    else
        $ROOT install -d "$(dirname "$dst")"
        $ROOT install -m "$mode" "$tmp" "$dst"
    fi
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# System configuration
# ---------------------------------------------------------------------------
backup_file /etc/environment
backup_file /etc/sddm.conf.d/10-autologin.conf
backup_file /etc/X11/xorg.conf.d/99-intel-only.conf

printf 'vkms\n' | $ROOT tee /etc/modules-load.d/vkms.conf >/dev/null
cat <<'RULE' | $ROOT tee /etc/udev/rules.d/99-vkms.rules >/dev/null
SUBSYSTEM=="drm", KERNEL=="card*", SUBSYSTEMS=="faux", KERNELS=="vkms", SYMLINK+="dri/vkms", GROUP="video", MODE="0660"
RULE
$ROOT udevadm control --reload 2>/dev/null || true
$ROOT udevadm trigger --subsystem-match=drm 2>/dev/null || true

# Physical Hyprland must never use VKMS; physical host must only see its monitors.
if [[ -f /etc/environment ]]; then
    $ROOT sed -i '/^AQ_DRM_DEVICES=/d; /^LIBSEAT_BACKEND=/d' /etc/environment
fi
printf 'AQ_DRM_DEVICES=%s\nLIBSEAT_BACKEND=logind\n' "$PHYS_CARD" |
    $ROOT tee -a /etc/environment >/dev/null

if lspci 2>/dev/null | grep -qi 'Intel.*VGA'; then
    install_rendered "$FILES/system/xorg/99-intel-only.conf" \
        /etc/X11/xorg.conf.d/99-intel-only.conf 644
else
    warn "no Intel VGA detected; skipping Xorg Intel-only config"
    warn "the physical display manager may claim VKMS and block the hidden session"
fi

if [[ "$VNC_AUTOLOGIN" == "1" ]]; then
    install_rendered "$FILES/system/sddm/10-autologin.conf" \
        /etc/sddm.conf.d/10-autologin.conf 644
    warn "SDDM autologin enabled for $TARGET_USER"
else
    warn "SDDM autologin disabled; :5901 needs a physical login after reboot"
fi

# The hidden service starts its own private seatd on /run/seatd.sock.
if systemctl is-enabled seatd.service >/dev/null 2>&1; then
    touch /var/lib/end4-pC-vnc/seatd-was-enabled
    $ROOT systemctl disable --now seatd.service 2>/dev/null || true
fi

if command -v ufw >/dev/null 2>&1 && $ROOT ufw status 2>/dev/null | grep -qi active; then
    $ROOT ufw allow from 100.64.0.0/10 to any port "$VNC_MIRROR_PORT" proto tcp comment 'end4-pC VNC mirror' || true
    $ROOT ufw allow from 100.64.0.0/10 to any port "$VNC_HIDDEN_PORT" proto tcp comment 'end4-pC VNC hidden' || true
    if [[ "$VNC_AUDIO" == sunshine ]]; then
        $ROOT ufw allow from 100.64.0.0/10 to any port 47984,47989,47990,48010 proto tcp comment 'end4-pC Sunshine' || true
        $ROOT ufw allow from 100.64.0.0/10 to any port 47998,47999,48000,48002 proto udp comment 'end4-pC Sunshine' || true
    fi
fi

install_rendered "$FILES/system/hyprland-hidden.service" \
    /etc/systemd/system/hyprland-hidden.service 644
install_rendered "$FILES/system/hyprland-hidden-run" \
    /usr/local/bin/hyprland-hidden-run 755
install_rendered "$FILES/system/hyprland-hidden-start" \
    /usr/local/bin/hyprland-hidden-start 755

$ROOT systemctl daemon-reload
$ROOT systemctl enable hyprland-hidden.service

# ---------------------------------------------------------------------------
# User configuration
# ---------------------------------------------------------------------------
backup_file "$TARGET_HOME/.config/hypr/remote.lua"
install_rendered "$FILES/user/hypr-remote.lua" \
    "$TARGET_HOME/.config/hypr/remote.lua" 644 user
install_rendered "$FILES/user/wayvnc/mirror.conf" \
    "$TARGET_HOME/.config/wayvnc/mirror.conf" 644 user
install_rendered "$FILES/user/wayvnc/remote.conf" \
    "$TARGET_HOME/.config/wayvnc/remote.conf" 644 user
install_rendered "$FILES/user/scripts/vnc-theme-hooks.sh" \
    "$TARGET_HOME/.config/hypr/custom/scripts/vnc-theme-hooks.sh" 755 user
install_rendered "$FILES/user/scripts/vnc-theme-watch" \
    "$TARGET_HOME/.config/hypr/custom/scripts/vnc-theme-watch" 755 user
install_rendered "$FILES/user/systemd/wayvnc-mirror.service" \
    "$TARGET_HOME/.config/systemd/user/wayvnc-mirror.service" 644 user
install_rendered "$FILES/user/systemd/wayvnc-remote.service" \
    "$TARGET_HOME/.config/systemd/user/wayvnc-remote.service" 644 user
install_rendered "$FILES/user/systemd/vnc-theme-hooks.service" \
    "$TARGET_HOME/.config/systemd/user/vnc-theme-hooks.service" 644 user

# Physical-specific wallpaper helper for the theme hook.
phys_src=""
for candidate in \
    "$TARGET_HOME/.config/hypr/custom/scripts/__video_wallpaper.sh" \
    "$TARGET_HOME/.config/quickshell/end4-pC/scripts/wallpapers/__video_wallpaper.sh"; do
    [[ -x "$candidate" ]] && { phys_src="$candidate"; break; }
done
if [[ -n "$phys_src" ]]; then
    $ROOT install -d -o "$TARGET_USER" -g "$TARGET_GROUP" \
        "$TARGET_HOME/.config/hypr/custom/scripts/vnc-physical"
    $ROOT install -m 755 -o "$TARGET_USER" -g "$TARGET_GROUP" \
        "$phys_src" "$TARGET_HOME/.config/hypr/custom/scripts/vnc-physical/__video_wallpaper.sh"
else
    warn "video wallpaper script not found; wallpaper restore hook will be a no-op"
fi

# Always create the null sink so hidden audio does not leak to host speakers.
install_rendered "$FILES/user/pipewire/50-hypr-remote.conf" \
    "$TARGET_HOME/.config/pipewire/pipewire.conf.d/50-hypr-remote.conf" 644 user

if [[ "$VNC_AUDIO" == sunshine ]]; then
    if command -v sunshine >/dev/null 2>&1; then
        install_rendered "$FILES/user/sunshine/sunshine-remote.conf" \
            "$TARGET_HOME/.config/sunshine/sunshine-remote.conf" 644 user
        install_rendered "$FILES/user/systemd/sunshine-remote.service" \
            "$TARGET_HOME/.config/systemd/user/sunshine-remote.service" 644 user
    else
        warn "sunshine is not installed; audio setup skipped"
    fi
fi

run_as_target systemctl --user daemon-reload || warn "user systemd not reachable"
run_as_target systemctl --user enable wayvnc-mirror.service wayvnc-remote.service || warn "could not enable wayvnc units"
if [[ -d "$TARGET_HOME/.config/quickshell/end4-pC" ]]; then
    run_as_target systemctl --user enable vnc-theme-hooks.service || warn "could not enable VNC theme hooks"
else
    warn "end4-pC quickshell not found; VNC theme hooks not enabled"
fi
if [[ "$VNC_AUDIO" == sunshine ]] && command -v sunshine >/dev/null 2>&1; then
    run_as_target systemctl --user enable sunshine-remote.service || warn "could not enable Sunshine"
fi

if command -v pactl >/dev/null 2>&1; then
    if ! run_as_target pactl list short sinks 2>/dev/null | grep -q hypr_remote; then
        run_as_target pactl load-module module-null-sink sink_name=hypr_remote \
            sink_properties=device.description=HyprRemote >/dev/null 2>&1 ||
            warn "could not create hypr_remote sink now; it will load from PipeWire config at next login"
    fi
fi

log "installed"
log "  physical mirror: vnc://$VNC_BIND_ADDR:$VNC_MIRROR_PORT"
log "  hidden session:  vnc://$VNC_BIND_ADDR:$VNC_HIDDEN_PORT"
if [[ "$VNC_AUDIO" == sunshine ]]; then
    log "  Sunshine audio:   https://$VNC_BIND_ADDR:47990 (pair Moonlight manually)"
fi
log "Reboot to apply the hidden-session ordering and SDDM/autologin changes."
log "After reboot, log in locally once if autologin was disabled."
