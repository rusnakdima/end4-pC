#!/usr/bin/env bash
# Single entry point for the Hyprland video wallpaper.
#
#   __video_wallpaper.sh <video-file>   start: proxy + detached supervisor
#   __video_wallpaper.sh --prefetch f   build/reuse f's proxy without touching
#                                        the player; prints the file to play
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
# One proxy cache for every copy of this script: the checkout's copy also
# runs it (shell previews), and a per-directory PROXY_DIR would split the
# cache between the quickshell config and this custom dir — a file built by
# a preview would then be encoded again on the next apply.
PROXY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/custom/scripts/mpvpaper_proxies"
# ONE set of pidfiles and ONE log for every copy of this script. There are
# always two: the checkout's copy (shell previews start it) and the deployed
# copy (switchwall starts it). Each used to keep its pidfiles beside itself, so
# neither could stop the other's supervisor — the survivor respawned mpvpaper
# and the two fought over the single wallpaper layer, which is why a clip
# previewed after a still wallpaper then failed to apply. The deployed folder is
# the canonical location: it is what PROXY_DIR already points into.
RUNTIME_DIR="$(dirname "$PROXY_DIR")"
PIDFILE="$RUNTIME_DIR/.video_wallpaper.pid"
MPVPAPER_PIDFILE="$RUNTIME_DIR/.video_wallpaper.mpvpaper.pid"
LOGFILE="$RUNTIME_DIR/.video_wallpaper.log"

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

# A cancelled preview kills this script; without this its ffmpeg child kept
# encoding in the background and fought the apply that followed for the CPU
# and the iGPU, which is a large part of why a new clip took so long to start.
ENCODE_CHILD=""
kill_encode_child() {
    [ -n "${ENCODE_CHILD:-}" ] && kill "$ENCODE_CHILD" 2>/dev/null
    return 0
}
trap 'kill_encode_child; exit 0' TERM INT HUP
trap 'kill_encode_child' EXIT

# Runs a command in the background and waits, so the trap above can reach it:
# bash does not deliver a signal to a foreground child it is waiting on in a
# way that lets us clean up, and an orphaned 4K encode freezes the compositor
# just as surely as an unproxied wallpaper does.
run_ffmpeg() {
    "$@" &
    ENCODE_CHILD=$!
    wait "$ENCODE_CHILD"
    local rc=$?
    ENCODE_CHILD=""
    return "$rc"
}

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

# True when the path is a video clip — the same extension list switchwall.sh
# uses. It has to exist here as well: the supervisor's config check called
# switchwall's copy, got "command not found", treated that as "not a video"
# and exited, leaving no wallpaper player at all.
is_video() {
    local extension="${1##*.}"
    extension="${extension,,}"
    case "$extension" in
        mp4|webm|mkv|avi|mov|gif|m4v|wmv|flv|ogv|3gp|qt) return 0 ;;
        *) return 1 ;;
    esac
}

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

# Cache key: source path + mtime + size + the encoder contract. The last
# field is bumped whenever the filter/encoder changes, so a proxy built with
# the old stretching filter is never reused after the fix.
proxy_path_for() {
    local src="$1" mtime size key base
    mtime="$(stat -c %Y "$src" 2>/dev/null || echo 0)"
    size="$(stat -c %s "$src" 2>/dev/null || echo 0)"
    key="$(printf '%s|%s|%s|%sx%s@%s|encode-v2' \
        "$src" "$mtime" "$size" "$TARGET_W" "$TARGET_H" "$TARGET_FPS" \
        | sha1sum | cut -c1-16)"
    base="$(basename "${src%.*}")"
    printf '%s/%s-%s.mp4' "$PROXY_DIR" "$base" "$key"
}

encode_proxy() {
    # The temp name carries the PID: a preview and an apply of the same clip
    # can encode at the same time (and a killed preview leaves its ffmpeg
    # behind), and a shared temp name made one run `rm -f` the other's file —
    # the loser then renamed a half-written proxy into place and mpv played a
    # broken clip. Each run now writes its own temp and renames it on success;
    # last writer wins with a complete file either way.
    local src="$1" dst="$2" tmp="${2}.$$.part.mp4" locked=0
    mkdir -p "$(dirname "$dst")" 2>/dev/null || true
    # One encode per target. The picker's preview and the apply that follows
    # both ask for the same brand-new clip; without this they encoded it twice
    # in parallel, which doubled the wait and saturated the iGPU (the machine
    # freezing). The second caller waits, then usually finds the cache warm.
    # The lock lives on a file descriptor, so a killed caller releases it.
    if command -v flock >/dev/null 2>&1; then
        exec 8>"${dst}.lock" || return 1
        if ! flock -w 900 8; then
            log "WARNING: timed out waiting to encode $dst"
            return 1
        fi
        locked=1
    fi
    release_lock() {
        [ "$locked" -eq 1 ] && flock -u 8 2>/dev/null
        return 0
    }
    if [ -s "$dst" ]; then
        release_lock
        return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
    if run_ffmpeg ffmpeg -y -loglevel error -hwaccel vaapi -hwaccel_output_format vaapi \
        -i "$src" -vf "scale_vaapi=w=${TARGET_W}:h=${TARGET_H}:force_original_aspect_ratio=decrease:force_divisible_by=2" -r "$TARGET_FPS" \
        -an -c:v h264_vaapi -b:v 5M -f mp4 -movflags +faststart "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv -f "$tmp" "$dst"
        release_lock
        return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
    log "VAAPI encode failed, falling back to software encode"
    if run_ffmpeg ffmpeg -y -loglevel error -i "$src" -vf "scale=w=${TARGET_W}:h=${TARGET_H}:force_original_aspect_ratio=decrease:force_divisible_by=2" -r "$TARGET_FPS" \
        -an -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p -f mp4 -movflags +faststart "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv -f "$tmp" "$dst"
        release_lock
        return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
    release_lock
    return 1
}

# Prints the file that should be handed to mpvpaper.
#
# $2 = "strict" turns a failed proxy build into an error instead of falling
# back to the original. A source that needs a proxy (the 4K60 clips) freezes
# the compositor when mpvpaper decodes it directly — the player log shows one
# 3840x2160 60 fps load that way — so a strict caller that gets nothing must
# show a still frame instead of a frozen desktop.
resolve_playfile() {
    local src="$1" mode="${2:-}" proxy
    if ! source_needs_proxy "$src"; then
        printf '%s\n' "$src"
        return 0
    fi
    mkdir -p "$PROXY_DIR" || true
    # A killed encode (preview cancelled, shell restarted) leaves its temp
    # behind. Sweep anything older than a day so the cache does not collect a
    # corpse for every interrupted run.
    find "$PROXY_DIR" -maxdepth 1 -name '*.part.mp4' -mmin +1440 -delete 2>/dev/null || true
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
    if [ "$mode" = "strict" ]; then
        log "ERROR: proxy encoding failed for $src; not falling back to the original"
        return 1
    fi
    log "WARNING: proxy encoding failed, playing the original file"
    printf '%s\n' "$src"
}

# --------------------------------------------------------------------------
# supervisor
# --------------------------------------------------------------------------
supervise() {
    local src="$1" playfile child configured
    # Any termination signal must end the supervisor, otherwise the restart
    # loop would immediately spawn a new mpvpaper after --stop. Killing the
    # in-flight encode with it matters too: an orphaned 4K encode keeps
    # burning the GPU long after its caller is gone.
    trap 'kill_encode_child; rm -f "$MPVPAPER_PIDFILE" 2>/dev/null; exit 0' TERM INT HUP
    echo $$ >"$PIDFILE"
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
        # Follow the wallpaper when it moved on: a keep-player apply adopts the
        # running player without restarting it, so this supervisor would still
        # hold the clip it was launched with, and a later player death would
        # bring a PREVIOUS clip back. Only ever adopt a newer *clip* — a still
        # wallpaper never exits the supervisor here, because switchwall stops
        # the player itself in that case and a preview may legitimately have
        # started this one for a clip that is not the configured wallpaper yet.
        configured="$(jq -r '.background.wallpaperPath // ""' "${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json" 2>/dev/null)"
        if [ -n "$configured" ] && is_video "$configured" && [ -f "$configured" ]; then
            src="$configured"
        fi
        # Resolved here, not once at start: the proxy may not have existed yet
        # when the supervisor came up, and a strict failure must retry the
        # build instead of handing mpvpaper a raw 4K source that freezes the
        # compositor. The poster stays on screen until this succeeds.
        playfile="$(resolve_playfile "$src" strict)" || playfile=""
        if [ -z "$playfile" ]; then
            log "ERROR: no playable file for $src yet, retrying in ${backoff}s"
            sleep "$backoff"
            backoff=$(( backoff < 60 ? backoff * 2 : 60 ))
            continue
        fi
        log "supervising mpvpaper on file $playfile"
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
    local sup="" child="" signalled=0
    if [ -f "$PIDFILE" ]; then
        sup="$(cat "$PIDFILE" 2>/dev/null || true)"
    fi
    # Kill the supervisor FIRST so it cannot respawn the child.
    if [ -n "$sup" ]; then
        kill -TERM "$sup" 2>/dev/null || true
        kill -TERM -- "-$sup" 2>/dev/null || true
        signalled=1
    fi
    # Only wait when something was actually signalled. Three unconditional
    # sleeps ran even with no player at all, so switching from a still
    # wallpaper to a video paid a full second of them before mpvpaper could
    # even be started.
    [ "$signalled" -eq 1 ] && sleep 0.3
    if [ -f "$MPVPAPER_PIDFILE" ]; then
        child="$(cat "$MPVPAPER_PIDFILE" 2>/dev/null || true)"
    fi
    if [ -n "$child" ]; then
        kill -TERM "$child" 2>/dev/null || true
        kill -KILL "$child" 2>/dev/null || true
        signalled=1
    fi
    if [ -n "$sup" ]; then
        kill -KILL -- "-$sup" 2>/dev/null || true
    fi
    # Fallback: exact process-name match (never -f, the supervisor argv
    # contains the word "mpvpaper").
    if /usr/bin/pkill -x mpvpaper 2>/dev/null; then
        sleep 0.3
        /usr/bin/pkill -9 -x mpvpaper 2>/dev/null || true
    fi
    # Kill supervisors by script NAME, never by path: this script always exists
    # twice (the checkout copy a shell preview starts, the deployed copy
    # switchwall starts) and a path-scoped pattern only ever matched its own —
    # the other copy's supervisor survived, respawned mpvpaper, and the two
    # players fought over the one wallpaper layer. The name pattern never
    # matches the "--stop"/"--prefetch" invocation itself.
    if /usr/bin/pkill -f "__video_wallpaper.sh --supervise" 2>/dev/null; then
        sleep 0.3
        /usr/bin/pkill -9 -f "__video_wallpaper.sh --supervise" 2>/dev/null || true
    fi
    /usr/bin/pkill -x mpvpaper 2>/dev/null || true
    rm -f "$PIDFILE" "$MPVPAPER_PIDFILE" 2>/dev/null || true
    # mpvpaper is killed with SIGKILL here, so it never gets to unlink its own
    # IPC socket. A leftover socket file lies to every later check: a
    # colours-only run refuses to restart a player that is not there, and a
    # preview appears to reach one that is not running.
    rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mpvpaper-"*.sock 2>/dev/null || true
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
        --prefetch)
            shift
            # Build (or reuse) the proxy for a file WITHOUT starting or
            # stopping anything: callers run this BEFORE killing the current
            # player so the old wallpaper keeps playing during the encode.
            # Prints the file that should be handed to mpvpaper, and nothing
            # at all when a proxy was required and could not be built — the
            # caller shows the still instead of freezing on the raw source.
            resolve_playfile "${1:-}" strict
            ;;
        --proxy-path)
            shift
            # Print the CACHED proxy for this source, and build nothing. The
            # picker's cell preview decodes this instead of the original clip:
            # a 4K60 source decoded twice at once (wallpaper + cell) is what
            # made the hover preview stutter.
            if [ ! -f "${1:-}" ] || ! source_needs_proxy "${1:-}"; then
                exit 0
            fi
            mkdir -p "$PROXY_DIR" 2>/dev/null || true
            proxy="$(proxy_path_for "${1:-}")"
            if [ -s "$proxy" ]; then
                printf '%s\n' "$proxy"
            fi
            ;;
        --supervise)
            shift
            supervise "$@"
            ;;
        "")
            log "usage: $0 <video-file> | --prefetch <file> | --stop"
            return 1
            ;;
        *)
            start_video_wallpaper "$1"
            ;;
    esac
}

main "$@"
