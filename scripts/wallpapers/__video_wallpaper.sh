#!/usr/bin/env bash
# Single entry point for the Hyprland video wallpaper.
#
#   __video_wallpaper.sh <video-file>   start: proxy + detached supervisor
#   __video_wallpaper.sh --stop         stop: supervisor + mpvpaper, deterministically
#
# One mpvpaper instance covers ALL outputs (one decode, one layer surface per
# output).  The supervisor keeps it alive so the wallpaper never stops.
# The supervisor is started with setsid, so it is a session/process-group
# leader and can be torn down as a whole.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
PROXY_DIR="$SCRIPT_DIR/mpvpaper_proxies"
PIDFILE="$SCRIPT_DIR/.video_wallpaper.pid"
MPVPAPER_PIDFILE="$SCRIPT_DIR/.video_wallpaper.mpvpaper.pid"
LOGFILE="$SCRIPT_DIR/.video_wallpaper.log"

# Proxy target: cover resolution for the 1920x1200 16:10 panel (and for
# 1920x1080), 30 fps.  Decoding the 4K60 original saturates the AMD iGPU
# (98-99% gpu_busy) and freezes the compositor; the proxy stays at ~43%.
TARGET_W=2134
TARGET_H=1200
TARGET_FPS=30

# NVIDIA's EGL vendor json sorts before mesa's, which would create a
# cross-vendor swap chain on the AMD render node.
MESA_EGL_VENDOR_JSON="/usr/share/glvnd/egl_vendor.d/50_mesa.json"

# mpvpaper's -o option is not usable here: mpvpaper writes it to
# /tmp/mpvpaper_<pid>.config and calls fopen() without checking the result.
# When /tmp is not writable by the user, fopen() returns NULL and mpvpaper
# segfaults on startup, which the supervisor then turns into a restart loop
# that eats a whole core.  The options are therefore passed through a private
# mpv configuration directory instead, which mpv reads from
# $XDG_CONFIG_HOME/mpv/mpv.conf.
#
# The control socket lives in the same place: the shell pauses and resumes
# the wallpaper through it (services/LiveWallpaper.qml).
MPVCONF_DIR="$SCRIPT_DIR/mpvpaper_conf"

# One control socket for the single mpvpaper instance that covers all
# outputs.  The shell globs "$XDG_RUNTIME_DIR/mpvpaper-*.sock".
MPV_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mpvpaper-wallpaper.sock"

log() { printf '[video-wallpaper] %s\n' "$*" >&2; }

# Writes the mpv configuration used by the wallpaper.
#
# mpv reads $XDG_CONFIG_HOME/mpv/mpv.conf, so pointing XDG_CONFIG_HOME at a
# private directory keeps the wallpaper's settings isolated from the user's
# own mpv.conf while still allowing the control socket to be set.
write_mpv_conf() {
    local dir="$MPVCONF_DIR"
    mkdir -p "$dir/mpv" || return 1
    {
        # mpv config syntax: one option per line, no leading dashes.
        printf '%s\n' "no-audio"
        printf '%s\n' "loop=inf"
        printf '%s\n' "hwdec=vaapi,auto"
        printf '%s\n' "panscan=1"
        printf '%s\n' "input-ipc-server=${MPV_SOCKET}"
    } >"$dir/mpv/mpv.conf" || return 1
    return 0
}

# --------------------------------------------------------------------------
# session environment
# --------------------------------------------------------------------------
ensure_session_env() {
    if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d /run/user/1000 ]; then
        export XDG_RUNTIME_DIR=/run/user/1000
    fi
    if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        export WAYLAND_DISPLAY=wayland-1
    fi
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        local sig
        sig="$(ls -t "${XDG_RUNTIME_DIR:-/run/user/1000}/hypr/" 2>/dev/null | head -n1)"
        [ -n "$sig" ] && export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    fi
    return 0
}

# Re-derive the session coordinates when the compositor has been restarted
# underneath us: a stale HYPRLAND_INSTANCE_SIGNATURE or a vanished Wayland
# socket makes mpvpaper exit immediately with "Unable to connect to the
# compositor", and the supervisor would then spin on a dead session forever.
refresh_session_env() {
    local rt="${XDG_RUNTIME_DIR:-/run/user/1000}" sig
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ ! -d "$rt/hypr/${HYPRLAND_INSTANCE_SIGNATURE}" ]; then
        unset HYPRLAND_INSTANCE_SIGNATURE
    fi
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ ! -S "$rt/${WAYLAND_DISPLAY}" ]; then
        unset WAYLAND_DISPLAY
    fi
    ensure_session_env
    if [ -z "${WAYLAND_DISPLAY:-}" ] || [ ! -S "$rt/${WAYLAND_DISPLAY}" ]; then
        local sock
        sock="$(ls -t "$rt"/wayland-* 2>/dev/null | head -n1)"
        if [ -n "$sock" ]; then
            export WAYLAND_DISPLAY="$(basename "$sock")"
        fi
    fi
    sig="$(ls -t "$rt/hypr/" 2>/dev/null | head -n1)"
    if [ -n "$sig" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    fi
    return 0
}

# --------------------------------------------------------------------------
# proxy handling
# --------------------------------------------------------------------------

# True when the source is bigger than the proxy target or runs faster than the
# target frame rate, i.e. when a downscale/cap is worth doing.
source_needs_proxy() {
    local src="$1" info="" w="" h="" fr="" num="" den=""
    info="$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,r_frame_rate -of csv=p=0:s=, "$src" 2>/dev/null)"
    [ -n "$info" ] || return 0
    IFS=, read -r w h fr <<<"$info"
    [ -n "$w" ] && [ -n "$h" ] || return 0
    num="${fr%%/*}"
    den="${fr##*/}"
    [ -n "$den" ] && [ "$den" != "0" ] || den=1
    if [ "$w" -gt "$TARGET_W" ] || [ "$h" -gt "$TARGET_H" ]; then
        return 0
    fi
    if [ "$((num * 1))" -gt "$((TARGET_FPS * den))" ]; then
        return 0
    fi
    return 1
}

# Cache key: source path + mtime + size.
proxy_path_for() {
    local src="$1" mtime size key base
    mtime="$(stat -c %Y "$src" 2>/dev/null || echo 0)"
    size="$(stat -c %s "$src" 2>/dev/null || echo 0)"
    key="$(printf '%s|%s|%s' "$src" "$mtime" "$size" | sha1sum | cut -c1-16)"
    base="$(basename "${src%.*}")"
    printf '%s/%s-%s.mp4' "$PROXY_DIR" "$base" "$key"
}

encode_proxy() {
    local src="$1" dst="$2" tmp="${2}.part.mp4"
    rm -f "$tmp" 2>/dev/null || true
    if ffmpeg -y -loglevel error -hwaccel vaapi -hwaccel_output_format vaapi \
        -i "$src" -vf "scale_vaapi=w=${TARGET_W}:h=${TARGET_H}" -r "$TARGET_FPS" \
        -c:v h264_vaapi -b:v 5M -f mp4 -movflags +faststart "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv -f "$tmp" "$dst"
        return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
    log "VAAPI encode failed, falling back to software encode"
    if ffmpeg -y -loglevel error -i "$src" -vf "scale=${TARGET_W}:${TARGET_H}" -r "$TARGET_FPS" \
        -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p -f mp4 -movflags +faststart "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv -f "$tmp" "$dst"
        return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
    return 1
}

# Prints the file that should be handed to mpvpaper.
resolve_playfile() {
    local src="$1" proxy
    if ! source_needs_proxy "$src"; then
        printf '%s\n' "$src"
        return 0
    fi
    mkdir -p "$PROXY_DIR" || true
    proxy="$(proxy_path_for "$src")"
    if [ -s "$proxy" ]; then
        log "using cached proxy $proxy"
        printf '%s\n' "$proxy"
        return 0
    fi
    log "encoding proxy $proxy ..."
    if encode_proxy "$src" "$proxy" && [ -s "$proxy" ]; then
        printf '%s\n' "$proxy"
        return 0
    fi
    rm -f "$proxy" 2>/dev/null || true
    log "WARNING: proxy encoding failed, playing the original file"
    printf '%s\n' "$src"
}

# --------------------------------------------------------------------------
# supervisor
# --------------------------------------------------------------------------
supervise() {
    local src="$1" playfile child
    # Any termination signal must end the supervisor, otherwise the restart
    # loop would immediately spawn a new mpvpaper after --stop.
    trap 'rm -f "$MPVPAPER_PIDFILE" 2>/dev/null; exit 0' TERM INT HUP
    echo $$ >"$PIDFILE"
    playfile="$(resolve_playfile "$src")"
    log "supervising mpvpaper on file $playfile"
    if [ -f "$MESA_EGL_VENDOR_JSON" ]; then
        export __EGL_VENDOR_LIBRARY_FILENAMES="$MESA_EGL_VENDOR_JSON"
    else
        log "WARNING: $MESA_EGL_VENDOR_JSON missing, running without the EGL override"
    fi
    # Bound the log: mpvpaper prints a status line for every frame, which
    # would otherwise grow the file without limit.
    local logsize=0
    # Restart backoff.  A hard failure (no compositor, unreadable file) must
    # not turn into a hot restart loop: every attempt burns a core for as
    # long as mpvpaper lives before it dies again.
    local backoff=2
    while :; do
        logsize="$(stat -c %s "$LOGFILE" 2>/dev/null || echo 0)"
        if [ "$logsize" -gt 2097152 ]; then
            tail -c 262144 "$LOGFILE" >"$LOGFILE.trim" 2>/dev/null &&
                mv -f "$LOGFILE.trim" "$LOGFILE" || rm -f "$LOGFILE.trim" 2>/dev/null || true
        fi
        # A compositor restart invalidates the session coordinates; re-derive
        # them so the restart loop does not spin on a dead session.
        refresh_session_env
        if ! write_mpv_conf; then
            log "ERROR: cannot write mpv configuration in $MPVCONF_DIR"
            sleep "$backoff"
            backoff=$(( backoff < 60 ? backoff * 2 : 60 ))
            continue
        fi
        # -p: pause the wallpaper while it is fully covered by a window.
        # Without it the video keeps decoding and rendering behind every
        # maximized window, which is the bulk of the idle CPU cost.
        # The options come from the private mpv configuration above, not
        # from -o: see the comment on MPVCONF_DIR.
        XDG_CONFIG_HOME="$MPVCONF_DIR" mpvpaper -p ALL "$playfile" &
        child=$!
        echo "$child" >"$MPVPAPER_PIDFILE"
        wait "$child"
        rm -f "$MPVPAPER_PIDFILE" 2>/dev/null || true
        log "mpvpaper exited, restarting in ${backoff}s"
        sleep "$backoff"
        # A run that lasted a while means the wallpaper was healthy, so the
        # next failure starts over with a short delay.
        backoff=2
    done
}

# --------------------------------------------------------------------------
# stop
# --------------------------------------------------------------------------
stop_video_wallpaper() {
    local sup="" child=""
    if [ -f "$PIDFILE" ]; then
        sup="$(cat "$PIDFILE" 2>/dev/null || true)"
    fi
    # Kill the supervisor FIRST so it cannot respawn the child.
    if [ -n "$sup" ]; then
        kill -TERM "$sup" 2>/dev/null || true
        kill -TERM -- "-$sup" 2>/dev/null || true
    fi
    sleep 0.3
    if [ -f "$MPVPAPER_PIDFILE" ]; then
        child="$(cat "$MPVPAPER_PIDFILE" 2>/dev/null || true)"
    fi
    if [ -n "$child" ]; then
        kill -TERM "$child" 2>/dev/null || true
        kill -KILL "$child" 2>/dev/null || true
    fi
    if [ -n "$sup" ]; then
        kill -KILL -- "-$sup" 2>/dev/null || true
    fi
    # Fallback: exact process-name match (never -f, the supervisor argv
    # contains the word "mpvpaper").
    /usr/bin/pkill -x mpvpaper 2>/dev/null || true
    sleep 0.3
    /usr/bin/pkill -9 -x mpvpaper 2>/dev/null || true
    # A second supervisor can survive a pidfile overwrite (e.g. when two
    # starts race), and every supervisor spawns its own mpvpaper.  Kill all
    # supervisors of this script: the pattern is distinctive and never
    # matches the "--stop" invocation itself.
    /usr/bin/pkill -f "$SCRIPT_PATH --supervise" 2>/dev/null || true
    sleep 0.3
    /usr/bin/pkill -9 -f "$SCRIPT_PATH --supervise" 2>/dev/null || true
    /usr/bin/pkill -x mpvpaper 2>/dev/null || true
    rm -f "$PIDFILE" "$MPVPAPER_PIDFILE" 2>/dev/null || true
    return 0
}

# --------------------------------------------------------------------------
# start
# --------------------------------------------------------------------------
start_video_wallpaper() {
    local src="$1"
    if [ ! -f "$src" ]; then
        log "ERROR: no such video file: $src"
        return 1
    fi
    command -v mpvpaper >/dev/null 2>&1 || {
        log "ERROR: mpvpaper is not installed"
        return 1
    }
    ensure_session_env
    stop_video_wallpaper
    setsid "$SCRIPT_PATH" --supervise "$src" </dev/null >>"$LOGFILE" 2>&1 &
    # Wait for the supervisor to publish its pid.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$PIDFILE" ] && break
        sleep 0.1
    done
    if [ -s "$PIDFILE" ]; then
        log "started, supervisor pid $(cat "$PIDFILE")"
        return 0
    fi
    log "ERROR: supervisor did not start"
    return 1
}

main() {
    case "${1:-}" in
        --stop)
            stop_video_wallpaper
            ;;
        --supervise)
            shift
            supervise "$@"
            ;;
        "")
            log "usage: $0 <video-file> | --stop"
            return 1
            ;;
        *)
            start_video_wallpaper "$1"
            ;;
    esac
}

main "$@"
