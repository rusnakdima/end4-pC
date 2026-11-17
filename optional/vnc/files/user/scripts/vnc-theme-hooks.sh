#!/usr/bin/env bash
# Physical VNC theme hooks. Only touches the physical session
# (XDG_RUNTIME_DIR=@RUNTIME@), never the hidden /remote session.
set -u

MODE="${1:?start|stop}"
export XDG_RUNTIME_DIR=@RUNTIME@
export WAYLAND_DISPLAY=@WAYLAND_DISPLAY@
export HOME=@HOME@
export USER=@USER@
export LOGNAME=@USER@
export DBUS_SESSION_BUS_ADDRESS=unix:path=@RUNTIME@/bus
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t @RUNTIME@/hypr 2>/dev/null | head -n1)"

BASE=@HOME@/.config/hypr/custom/scripts
LOG="$BASE/vnc-theme-hooks.log"
PHYS="$BASE/vnc-physical/__video_wallpaper.sh"
CONFIG="$HOME/.config/illogical-impulse/config.json"
STATE="$BASE/.vnc-theme-walls-state.json"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

phys_pid() {
    tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | grep -qx 'XDG_RUNTIME_DIR=@RUNTIME@'
}

reload_physical_qs() {
    local pids=""
    for p in $(pgrep -f 'qs -p @HOME@/.config/quickshell/end4-pC' 2>/dev/null); do
        phys_pid "$p" && pids="$pids $p"
    done
    if [ -n "$pids" ]; then
        kill -TERM $pids 2>/dev/null || true
        sleep 1
        kill -KILL $pids 2>/dev/null || true
    fi
    log "restarting physical quickshell"
    setsid env \
        XDG_RUNTIME_DIR=@RUNTIME@ \
        WAYLAND_DISPLAY=@WAYLAND_DISPLAY@ \
        DBUS_SESSION_BUS_ADDRESS=unix:path=@RUNTIME@/bus \
        HOME=@HOME@ \
        /usr/bin/qs -p @HOME@/.config/quickshell/end4-pC \
        >>"$LOG" 2>&1 &
}

stop_physical_wallpaper() {
    for p in $(pgrep -f '__video_wallpaper.sh --supervise' 2>/dev/null); do
        phys_pid "$p" && kill "$p" 2>/dev/null || true
    done
    sleep 0.3
    for p in $(pgrep -x mpvpaper 2>/dev/null); do
        phys_pid "$p" && kill "$p" 2>/dev/null || true
    done
    rm -f @RUNTIME@/mpvpaper-*.sock
}

restore_physical_wallpaper() {
    local wallpaper=""
    if [ -f "$CONFIG" ]; then
        wallpaper="$(jq -r '.background.wallpaperPath // ""' "$CONFIG" 2>/dev/null || true)"
    fi
    if [ -n "$wallpaper" ] && [ -f "$wallpaper" ] && [ -x "$PHYS" ]; then
        log "restore wallpaper: $wallpaper"
        setsid "$PHYS" "$wallpaper" >>"$LOG" 2>&1 &
    else
        log "no restorable wallpaper (path='$wallpaper')"
    fi
}

blank_static_wallpaper() {
    [ -f "$CONFIG" ] || return 0
    [ -f "$STATE" ] && return 0
    local wp tp cw tmp
    wp="$(jq -r '.background.wallpaperPath // ""' "$CONFIG" 2>/dev/null || true)"
    tp="$(jq -r '.background.thumbnailPath // ""' "$CONFIG" 2>/dev/null || true)"
    cw="$(jq -r '.background.centeredWallpaperImage // ""' "$CONFIG" 2>/dev/null || true)"
    jq -n --arg wp "$wp" --arg tp "$tp" --arg cw "$cw" \
        '{wallpaperPath:$wp,thumbnailPath:$tp,centeredWallpaperImage:$cw}' >"$STATE" 2>/dev/null || return 0
    tmp="$(mktemp "${CONFIG}.XXXXXX")" || return 0
    if jq --arg wp "" --arg tp "" --arg cw "" \
        '.background.wallpaperPath=$wp | .background.thumbnailPath=$tp | .background.centeredWallpaperImage=$cw' \
        "$CONFIG" >"$tmp" 2>/dev/null; then
        cat "$tmp" >"$CONFIG"
        rm -f "$tmp"
        log "static wallpaper blanked"
        reload_physical_qs
    else
        rm -f "$tmp"
    fi
}

restore_static_wallpaper() {
    [ -f "$STATE" ] || return 0
    local wp tp cw tmp
    wp="$(jq -r '.wallpaperPath // ""' "$STATE" 2>/dev/null || true)"
    tp="$(jq -r '.thumbnailPath // ""' "$STATE" 2>/dev/null || true)"
    cw="$(jq -r '.centeredWallpaperImage // ""' "$STATE" 2>/dev/null || true)"
    tmp="$(mktemp "${CONFIG}.XXXXXX")" || return 0
    if jq --arg wp "$wp" --arg tp "$tp" --arg cw "$cw" \
        '.background.wallpaperPath=$wp | .background.thumbnailPath=$tp | .background.centeredWallpaperImage=$cw' \
        "$CONFIG" >"$tmp" 2>/dev/null; then
        cat "$tmp" >"$CONFIG"
        rm -f "$tmp"
        log "static wallpaper restored"
        reload_physical_qs
    else
        rm -f "$tmp"
    fi
    rm -f "$STATE"
}

case "$MODE" in
    start)
        log "VNC connected: stopping physical live wallpaper"
        stop_physical_wallpaper
        blank_static_wallpaper
        ;;
    stop)
        log "VNC disconnected: restoring physical wallpaper"
        restore_static_wallpaper
        restore_physical_wallpaper
        if [ "${VNC_THEME_LOCK:-1}" = "1" ]; then
            log "locking physical session"
            setsid /usr/bin/hyprlock >>"$LOG" 2>&1 &
        else
            log "locking disabled for test"
        fi
        ;;
    *)
        echo "usage: $0 start|stop" >&2
        exit 2
        ;;
esac
