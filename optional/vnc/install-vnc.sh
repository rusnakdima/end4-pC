#!/usr/bin/env bash
# DEPRECATED: this full/hidden VKMS installer is retired. It created a second
# Hyprland session and is not used by the Settings page. Use install-user.sh.
if [[ "${END4PC_VNC_LEGACY:-0}" != "1" ]]; then
    echo "install-vnc.sh is retired. Use ./install-user.sh for the supported user-level setup." >&2
    echo "Set END4PC_VNC_LEGACY=1 only if you intentionally need the old code." >&2
    exit 1
fi

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

pick_port() {
    local p="${1:-5901}"
    while ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p$"; do
        p=$((p + 1))
    done
    printf '%s\n' "$p"
}

VNC_MODE="${VNC_MODE:-full}"
VNC_MIRROR_PORT="${VNC_MIRROR_PORT:-$(pick_port 5901)}"
VNC_HIDDEN_PORT="${VNC_HIDDEN_PORT:-$(pick_port $((VNC_MIRROR_PORT + 1)))}"
VNC_AUDIO="${VNC_AUDIO:-sunshine}"
VNC_AUTOLOGIN="${VNC_AUTOLOGIN:-0}"
VNC_THEME_LOCK="${VNC_THEME_LOCK:-1}"
VNC_HIDDEN_OUTPUT="${VNC_HIDDEN_OUTPUT:-}"
VNC_MIRROR_INPUT="${VNC_MIRROR_INPUT:-1}"
VNC_WAYLAND_DISPLAY="${VNC_WAYLAND_DISPLAY:-}"
VNC_SESSION="${VNC_SESSION:-}"
VNC_SUNSHINE_NAME="${VNC_SUNSHINE_NAME:-}"

[[ "$VNC_MODE" == "full" || "$VNC_MODE" == "mirror" ]] || {
    warn "unknown VNC_MODE='$VNC_MODE'; using full"
    VNC_MODE=full
}

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
HOST_SHORT=$(hostname -s 2>/dev/null || hostname)

if [[ -z "${VNC_WAYLAND_DISPLAY:-}" ]]; then
    for sock in "$RUNTIME"/wayland-*; do
        [[ -S "$sock" ]] && { VNC_WAYLAND_DISPLAY=$(basename "$sock"); break; }
    done
fi
[[ -n "${VNC_WAYLAND_DISPLAY:-}" ]] || VNC_WAYLAND_DISPLAY=wayland-1

if [[ -z "${VNC_SESSION:-}" ]]; then
    if [[ -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
        VNC_SESSION=hyprland
    else
        VNC_SESSION=$(basename "$(find /usr/share/wayland-sessions -name '*.desktop' 2>/dev/null | head -n1)" .desktop)
        [[ -n "$VNC_SESSION" ]] || VNC_SESSION=hyprland
    fi
fi
[[ -n "${VNC_SUNSHINE_NAME:-}" ]] || VNC_SUNSHINE_NAME="$HOST_SHORT-hyprland"
log "mode=$VNC_MODE user=$TARGET_USER display=$VNC_WAYLAND_DISPLAY session=$VNC_SESSION"

# ---------------------------------------------------------------------------
# Dependencies and GPU discovery (full mode only)
# ---------------------------------------------------------------------------
if [[ "$VNC_MODE" == "full" ]]; then
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

# Physical GPU identity for a device-independent Xorg config.
PHYS_SYS=$(readlink -f "/sys/class/drm/$(basename "$PHYS_CARD")/device" 2>/dev/null || true)
PCI_SLOT="${PHYS_SYS##*/}"
VENDOR_ID=$(cat "$PHYS_SYS/vendor" 2>/dev/null || true)
case "$VENDOR_ID" in
    0x8086) XORG_DRIVER=modesetting ;;
    0x1002) XORG_DRIVER=amdgpu ;;
    0x10de) XORG_DRIVER=nvidia ;;
    *)      XORG_DRIVER=modesetting ;;
esac
XORG_BUSID=""
if [[ "$PCI_SLOT" =~ ^([0-9a-fA-F]+):([0-9a-fA-F]+):([0-9a-fA-F]+)\.([0-9a-fA-F]+)$ ]]; then
    XORG_BUSID=$(printf 'PCI:%d:%d:%d' \
        "$((16#${BASH_REMATCH[2]}))" \
        "$((16#${BASH_REMATCH[3]}))" \
        "$((16#${BASH_REMATCH[4]}))")
fi

# VKMS connector name is normally Virtual-1, but detect it from sysfs.
if [[ -z "${VNC_HIDDEN_OUTPUT:-}" ]]; then
    for st in /sys/class/drm/card*-Virtual-*/status; do
        [[ -f "$st" ]] || continue
        if [[ "$(cat "$st" 2>/dev/null)" == "connected" ]]; then
            VNC_HIDDEN_OUTPUT=$(basename "$(dirname "$st")")
            VNC_HIDDEN_OUTPUT=${VNC_HIDDEN_OUTPUT#*-}
            break
        fi
    done
fi
[[ -n "${VNC_HIDDEN_OUTPUT:-}" ]] || VNC_HIDDEN_OUTPUT=Virtual-1

log "VKMS=$VKMS_DEV physical=$PHYS_CARD render=$RENDER_DEV hidden=$VNC_HIDDEN_OUTPUT"
log "xorg driver=$XORG_DRIVER busid=${XORG_BUSID:-unknown}"
log "bind=$VNC_BIND_ADDR mirror=$VNC_MIRROR_PORT hidden=$VNC_HIDDEN_PORT audio=$VNC_AUDIO"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
if [[ "$VNC_MODE" == "full" ]]; then
    $ROOT install -d -m 755 "$BACKUP"
fi

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
        -e "s|@VKMS@|${VKMS_DEV:-}|g" \
        -e "s|@PHYS@|${PHYS_CARD:-}|g" \
        -e "s|@RENDER@|${RENDER_DEV:-}|g" \
        -e "s|@MIRROR_PORT@|$VNC_MIRROR_PORT|g" \
        -e "s|@HIDDEN_PORT@|$VNC_HIDDEN_PORT|g" \
        -e "s|@HIDDEN_OUTPUT@|${VNC_HIDDEN_OUTPUT:-Virtual-1}|g" \
        -e "s|@WAYLAND_DISPLAY@|$VNC_WAYLAND_DISPLAY|g" \
        -e "s|@SESSION@|$VNC_SESSION|g" \
        -e "s|@SUNSHINE_NAME@|$VNC_SUNSHINE_NAME|g" \
        -e "s|@XORG_DRIVER@|${XORG_DRIVER:-modesetting}|g" \
        -e "s|@XORG_BUSID@|${XORG_BUSID:-}|g" \
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

install_vnc_cli() {
    $ROOT install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/.local/bin"
    $ROOT install -m 755 -o "$TARGET_USER" -g "$TARGET_GROUP" \
        "$MOD_DIR/bin/end4pc-vnc" "$TARGET_HOME/.local/bin/end4pc-vnc"
}

# ---------------------------------------------------------------------------
# Mirror-only mode: expose the current physical session, no VKMS/system setup.
# ---------------------------------------------------------------------------
if [[ "$VNC_MODE" == "mirror" ]]; then
    if [[ $(id -u) -eq "$TARGET_UID" ]]; then
        ROOT=""
    fi

    for cmd in wayvnc; do
        command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required"
    done
    for cmd in jq grim hyprlock; do
        command -v "$cmd" >/dev/null 2>&1 || warn "$cmd missing; related theme hooks may be limited"
    done

    install_rendered "$FILES/user/wayvnc/mirror.conf" \
        "$TARGET_HOME/.config/wayvnc/mirror.conf" 644 user
    install_rendered "$FILES/user/systemd/wayvnc-mirror.service" \
        "$TARGET_HOME/.config/systemd/user/wayvnc-mirror.service" 644 user
    install_rendered "$FILES/user/scripts/wayvnc-mirror-run" \
        "$TARGET_HOME/.config/hypr/custom/scripts/wayvnc-mirror-run" 755 user
    install_vnc_cli

    if [[ -d "$TARGET_HOME/.config/quickshell/end4-pC" ]]; then
        install_rendered "$FILES/user/scripts/vnc-theme-hooks.sh" \
            "$TARGET_HOME/.config/hypr/custom/scripts/vnc-theme-hooks.sh" 755 user
        install_rendered "$FILES/user/scripts/vnc-theme-watch" \
            "$TARGET_HOME/.config/hypr/custom/scripts/vnc-theme-watch" 755 user
        install_rendered "$FILES/user/systemd/vnc-theme-hooks.service" \
            "$TARGET_HOME/.config/systemd/user/vnc-theme-hooks.service" 644 user
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
        fi
    fi

    $ROOT install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/.config/end4-pC"
    cat >"$CONFIG" <<CONF
# Generated by end4-pC optional VNC installer.
VNC_MODE="mirror"
VNC_USER="$TARGET_USER"
VNC_BIND_ADDR="$VNC_BIND_ADDR"
VNC_MIRROR_PORT="$VNC_MIRROR_PORT"
VNC_MIRROR_INPUT="$VNC_MIRROR_INPUT"
VNC_WAYLAND_DISPLAY="$VNC_WAYLAND_DISPLAY"
VNC_THEME_LOCK="$VNC_THEME_LOCK"
CONF
    chown "$TARGET_USER:$TARGET_GROUP" "$CONFIG" 2>/dev/null || true
    chmod 600 "$CONFIG" 2>/dev/null || true

    run_as_target systemctl --user daemon-reload || warn "user systemd not reachable"
    run_as_target systemctl --user enable --now wayvnc-mirror.service || warn "could not start wayvnc mirror"
    if [[ -f "$TARGET_HOME/.config/systemd/user/vnc-theme-hooks.service" ]]; then
        run_as_target systemctl --user enable --now vnc-theme-hooks.service || warn "could not start VNC theme hooks"
    fi

    if [[ $(id -u) -eq 0 ]] && command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
        ufw allow from 100.64.0.0/10 to any port "$VNC_MIRROR_PORT" proto tcp comment 'end4-pC VNC mirror' || true
    fi

    log "installed mirror-only VNC"
    log "  physical mirror: vnc://$VNC_BIND_ADDR:$VNC_MIRROR_PORT"
    log "  display=$VNC_WAYLAND_DISPLAY user=$TARGET_USER"
    exit 0
fi

# ---------------------------------------------------------------------------
# System configuration
# ---------------------------------------------------------------------------
backup_file /etc/environment
backup_file /etc/sddm.conf.d/10-autologin.conf
backup_file /etc/X11/xorg.conf.d/99-physical-only.conf
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

DISPLAY_SERVER=$(grep -Rhs '^DisplayServer=' /etc/sddm.conf /etc/sddm.conf.d 2>/dev/null | tail -n1 | cut -d= -f2 || true)
if [[ "${DISPLAY_SERVER:-x11}" == "wayland" ]]; then
    log "display manager is Wayland; skipping Xorg physical-only config"
elif [[ -n "${XORG_BUSID:-}" ]]; then
    install_rendered "$FILES/system/xorg/99-physical-only.conf" \
        /etc/X11/xorg.conf.d/99-physical-only.conf 644
    $ROOT rm -f /etc/X11/xorg.conf.d/99-intel-only.conf
    log "installed Xorg physical-only config: driver=$XORG_DRIVER busid=$XORG_BUSID"
else
    warn "physical GPU PCI BusID not detected; skipping Xorg config"
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
install_rendered "$FILES/user/scripts/wayvnc-mirror-run" \
    "$TARGET_HOME/.config/hypr/custom/scripts/wayvnc-mirror-run" 755 user
install_vnc_cli
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

# Generated runtime configuration: the CLI and settings page read this file.
$ROOT install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/.config/end4-pC"
cat >"$CONFIG" <<CONF
# Generated by end4-pC optional VNC installer.
VNC_MODE="full"
VNC_USER="$TARGET_USER"
VNC_BIND_ADDR="$VNC_BIND_ADDR"
VNC_MIRROR_PORT="$VNC_MIRROR_PORT"
VNC_HIDDEN_PORT="$VNC_HIDDEN_PORT"
VNC_MIRROR_INPUT="$VNC_MIRROR_INPUT"
VNC_WAYLAND_DISPLAY="$VNC_WAYLAND_DISPLAY"
VNC_SESSION="$VNC_SESSION"
VNC_HIDDEN_OUTPUT="$VNC_HIDDEN_OUTPUT"
VNC_SUNSHINE_NAME="$VNC_SUNSHINE_NAME"
VNC_AUDIO="$VNC_AUDIO"
VNC_AUTOLOGIN="$VNC_AUTOLOGIN"
VNC_THEME_LOCK="$VNC_THEME_LOCK"
VNC_THEME_BLANK_WALLPAPER="${VNC_THEME_BLANK_WALLPAPER:-1}"
CONF
chown "$TARGET_USER:$TARGET_GROUP" "$CONFIG" 2>/dev/null || true
chmod 600 "$CONFIG" 2>/dev/null || true

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
