#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

# When the shell decodes the video wallpaper itself, switchwall must not start
# mpvpaper (or leave a supervisor that respawns it). It still builds the proxy
# and the poster; the shell plays the proxy. Default true keeps a fresh config
# and the installer in the in-shell path.
IN_SHELL_VIDEO="true"
if [ -f "$SHELL_CONFIG_FILE" ]; then
    IN_SHELL_VIDEO=$(jq -r '.background.inShellVideo // true' "$SHELL_CONFIG_FILE" 2>/dev/null || echo true)
fi

# shellcheck source=../lib/config.sh
source "$SCRIPT_DIR/../lib/config.sh"

handle_kde_material_you_colors() {
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")
        if [ "$enable_qt_apps" == "false" ]; then
            return
        fi
    fi

    local kde_scheme_variant=""
    case "$type_flag" in
        scheme-content|scheme-expressive|scheme-fidelity|scheme-fruit-salad|scheme-monochrome|scheme-neutral|scheme-rainbow|scheme-tonal-spot)
            kde_scheme_variant="$type_flag"
            ;;
        *)
            kde_scheme_variant="scheme-tonal-spot"
            ;;
    esac

    # Konsole lock: the kde-material-you-colors wrapper also rewrites the
    # Konsole profiles' [Appearance] ColorScheme/Font to the generated
    # MaterialYou values. Snapshot the profiles first and restore them after
    # the wrapper runs so Konsole keeps the user's own color scheme while
    # every other app is still themed.
    KONSOLE_DIR="$HOME/.local/share/konsole"
    konsole_backup_dir="$STATE_DIR/user/generated/konsole-lock-backup"
    lock_konsole="true"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        lock_konsole=$(jq -r '.appearance.wallpaperTheming.lockKonsoleColors // "true"' "$SHELL_CONFIG_FILE")
    fi

    konsole_lock_backup() {
        [ ! -d "$konsole_backup_dir" ] && mkdir -p "$konsole_backup_dir"
        find "$KONSOLE_DIR" -maxdepth 1 -name "*.profile" -type f -exec cp -f {} "$konsole_backup_dir/" \;
    }

    konsole_lock_restore() {
        if [ -d "$konsole_backup_dir" ] && compgen -G "$konsole_backup_dir/*.profile" > /dev/null; then
            for f in "$konsole_backup_dir"/*.profile; do
                cp -f "$f" "$KONSOLE_DIR/$(basename "$f")" 2>/dev/null || true
            done
        fi
    }

    if [[ "$lock_konsole" == "true" && -d "$KONSOLE_DIR" ]]; then
        konsole_lock_backup
    fi

    "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$kde_scheme_variant"

    if [[ "$lock_konsole" == "true" ]]; then
        konsole_lock_restore
    fi

    # kde-material-you-colors rewrites the KDE icon theme from its own config.
    # Re-assert the managed theme after the wrapper, but only when the user
    # enabled the override (the manager enforces that policy).
    apply_icon_override_safety_net "$mode_flag"
}

pre_process() {
    local mode_flag="$1"
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
        for ini in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
            [[ -f "$ini" ]] || continue
            sed -i 's/^gtk-theme-name=.*/gtk-theme-name=adw-gtk3-dark/' "$ini"
            sed -i 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=true/' "$ini"
        done
        if [[ -f "$HOME/.config/kdeglobals" ]]; then
            sed -i 's/^ColorScheme=.*/ColorScheme=MaterialYouDark/' "$HOME/.config/kdeglobals"
        fi
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
        for ini in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
            [[ -f "$ini" ]] || continue
            sed -i 's/^gtk-theme-name=.*/gtk-theme-name=adw-gtk3/' "$ini"
            sed -i 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=false/' "$ini"
        done
        if [[ -f "$HOME/.config/kdeglobals" ]]; then
            sed -i 's/^ColorScheme=.*/ColorScheme=MaterialYouLight/' "$HOME/.config/kdeglobals"
        fi
    fi

    # Push the same mode to external GTK/Qt application windows. The inline
    # writes above are deliberately kept as a fallback when this script is
    # missing, so an incomplete deploy can never leave apps on the wrong side.
    local app_theming="$SCRIPT_DIR/../theming/app-theming.sh"
    if [[ -f "$app_theming" ]]; then
        bash "$app_theming" "$mode_flag" >/dev/null 2>&1 || true
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

update_icon_scheme() {
    local mode_flag="$1"
    local manager="$SCRIPT_DIR/../theming/icon-theme-manager.sh"
    [ -x "$manager" ] || return 0
    bash "$manager" --sync --apply --mode "$mode_flag" --source wallpaper || true
}

apply_icon_override_safety_net() {
    local mode_flag="$1"
    local manager="$SCRIPT_DIR/../theming/icon-theme-manager.sh"
    [ -x "$manager" ] || return 0
    bash "$manager" --post-kde --mode "$mode_flag" || true
}

post_process() {
    local screen_width="$1"
    local screen_height="$2"
    local wallpaper_path="$3"
    local colors_lock_flag="$4"

    if [[ -n "$colors_lock_flag" ]]; then
        return
    fi

    "$SCRIPT_DIR/code/material-code-set-color.sh" &
}

apply_named_scheme() {
    local mode_flag="$1"
    local wallpaper_path="$2"
    python3 "$SCRIPT_DIR/named_scheme.py" \
        --scheme "$named_scheme" \
        --mode "$mode_flag" \
        --image "$wallpaper_path" \
        --primary "$named_primary" \
        --secondary "$named_secondary" \
        --scss "$STATE_DIR/user/generated/material_colors.scss" \
        --cache "$STATE_DIR/user/generated/color.txt" || {
            notify-send "Color scheme" "'$named_scheme' is invalid, going back to Material colors" -a "Shell"
            config_json_update "$SHELL_CONFIG_FILE" '.appearance.palette.namedScheme = ""'
            return 1
        }
    "$SCRIPT_DIR"/applycolor.sh
    update_icon_scheme "$mode_flag"
    apply_named_qt &
    "$SCRIPT_DIR/code/material-code-set-color.sh" &
}

apply_named_qt() {
    if [ -f "$SHELL_CONFIG_FILE" ] && [ "$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")" == "false" ]; then
        return
    fi
    command -v plasma-apply-colorscheme >/dev/null || return
    plasma-apply-colorscheme IllogicalNamed2 >/dev/null 2>&1
    plasma-apply-colorscheme IllogicalNamed >/dev/null 2>&1
}

check_and_prompt_upscale() {
    local img="$1"
    if [ -f "$SHELL_CONFIG_FILE" ] && [ "$(jq -r '.background.collage.enable // false' "$SHELL_CONFIG_FILE")" == "true" ]; then
        return
    fi
    min_width_desired="$(monitor_value '([.[].width] | max)' 1920)"
    min_height_desired="$(monitor_value '([.[].height] | max)' 1080)"

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            img_width=$(identify -format "%w" "$img" 2>/dev/null)
            img_height=$(identify -format "%h" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            action=$(notify-send "Upscale?" \
                "Image resolution (${img_width}x${img_height}) is lower than screen resolution (${min_width_desired}x${min_height_desired})" \
                -A "open_upscayl=Open Upscayl"\
                -a "Wallpaper switcher")
            if [[ "$action" == "open_upscayl" ]]; then
                if command -v upscayl &>/dev/null; then
                    nohup upscayl > /dev/null 2>&1 &
                else
                    action2=$(notify-send \
                        -a "Wallpaper switcher" \
                        -c "im.error" \
                        -A "install_upscayl=Install Upscayl (Arch)" \
                        "Install Upscayl?" \
                        "yay -S upscayl-bin")
                    if [[ "$action2" == "install_upscayl" ]]; then
                        if command -v yay &>/dev/null; then
                            kitty -1 yay -S upscayl-bin
                        elif command -v paru &>/dev/null; then
                            kitty -1 paru -S upscayl-bin
                        else
                            kitty -1 sudo pacman -S upscayl-bin
                        fi
                        if command -v upscayl &>/dev/null; then
                            nohup upscayl > /dev/null 2>&1 &
                        fi
                    fi
                fi
            fi
        fi
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
VIDEO_WALLPAPER_SCRIPT="$RESTORE_SCRIPT_DIR/__video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
LAST_THUMBNAIL="$THUMBNAIL_DIR/.last-good.jpg"
MPVPAPER_FLAGS="-p -a max"
# One control socket per output, so the shell can pause and resume the live
# wallpaper instead of only being able to kill it.
MPV_SOCKET_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
MPV_SOCKET_PREFIX="$MPV_SOCKET_DIR/mpvpaper-"

# mpvpaper's -o option is unusable here: mpvpaper writes it to
# /tmp/mpvpaper_<pid>.config with an unchecked fopen(). When /tmp is not
# writable by the user, fopen() returns NULL and mpvpaper segfaults on
# startup, so the wallpaper never appears and every restart burns a core.
# The options are passed through a private mpv configuration directory
# instead, which mpv reads from $XDG_CONFIG_HOME/mpv/mpv.conf.
MPV_CONF_ROOT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mpvpaper-conf"

# Writes the mpv configuration for one mpvpaper instance.
write_mpv_conf() {
    local dir="$1"
    local socket="$2"
    mkdir -p "$dir/mpv" || return 1
    {
        # mpv config syntax: one option per line, no leading dashes.
        printf '%s\n' "no-audio" "loop=inf" "hwdec=auto" "scale=bilinear"
        printf '%s\n' "interpolation=no" "video-sync=display-resample"
        printf '%s\n' "panscan=1.0" "video-scale-x=1.0" "video-scale-y=1.0"
        printf '%s\n' "video-align-x=0.5" "video-align-y=0.5" "load-scripts=no"
        printf 'input-ipc-server=%s\n' "$socket"
    } >"$dir/mpv/mpv.conf" || return 1
    return 0
}

is_video() {
    local extension="${1##*.}"
    extension="${extension,,}"
    case "$extension" in
        mp4|webm|mkv|avi|mov|gif|m4v|wmv|flv|ogv|3gp|qt) return 0 ;;
        *) return 1 ;;
    esac
}

# One switchwall at a time. The lock is a DIRECTORY, not flock: a locked file
# descriptor is inherited by every child, and the video supervisor is spawned
# from this script — it lived for the rest of the session holding the lock, so
# every later apply queued for the full timeout and a clip only landed on the
# 4th or 5th click, while the queued runs then applied old videos in turn.
# mkdir is atomic and children inherit nothing.
# Hand $1 to the running player and make sure it is not left paused — the
# same loadfile the picker's preview uses. Returns 0 when a player took it.
# This is how an apply switches clips without tearing the player down: a
# kill+restart leaves a ~3 second hole in which the wallpaper is only a still
# picture, which reads as "applied but not playing".
player_loadfile() {
    local want="$1" sock=""
    command -v python3 >/dev/null 2>&1 || return 1
    for sock in "${MPV_SOCKET_PREFIX}"*.sock; do
        [[ -S "$sock" ]] || continue
        if python3 -c 'import socket, sys, json
sk = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sk.settimeout(2)
try:
    sk.connect(sys.argv[1])
except Exception:
    sys.exit(1)
sk.sendall((json.dumps({"command": ["loadfile", sys.argv[2], "replace"]}) + chr(10)).encode())
sk.sendall((json.dumps({"command": ["set_property", "pause", False]}) + chr(10)).encode())
sk.close()' "$sock" "$want" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

SWITCHWALL_LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/switchwall.lock.d"
SWITCHWALL_LOCK_TAKEN=0
# Colours are serialised separately from the wallpaper/player switch: colour
# generation is by far the slowest part of a run (a still takes ~16 s), and
# holding the whole run behind it made the NEXT apply wait for six seconds
# before it could even start — which is what an image -> video switch paid,
# with nothing happening on screen the whole time.
COLORS_LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/switchwall.colors.lock.d"
COLORS_LOCK_TAKEN=0

# A run killed mid-way cannot rmdir its directory. Ten minutes is not a live
# run any more; stat gives second granularity (find's -mmin does not).
switchwall_lock_is_stale() {
    local dir="$1" now m
    now="$(date +%s)"
    m="$(stat -c %Y "$dir" 2>/dev/null || echo "$now")"
    [ $(( now - m )) -gt 600 ]
}

switchwall_release_lock() {
    if [ "${SWITCHWALL_LOCK_TAKEN:-0}" -eq 1 ]; then
        rmdir "$SWITCHWALL_LOCK" 2>/dev/null || true
        SWITCHWALL_LOCK_TAKEN=0
    fi
    if [ "${COLORS_LOCK_TAKEN:-0}" -eq 1 ]; then
        rmdir "$COLORS_LOCK" 2>/dev/null || true
        COLORS_LOCK_TAKEN=0
    fi
    return 0
}

# $1 = lock directory, $2 = name of the variable to set to 1 once held.
switchwall_take_lock() {
    local dir="$1" var="$2" waited=0
    while ! mkdir "$dir" 2>/dev/null; do
        if switchwall_lock_is_stale "$dir"; then
            rm -rf "$dir" 2>/dev/null
            continue
        fi
        waited=$((waited + 1))
        # Never make the user wait forever: after a minute it is better to
        # risk two runs than to watch nothing happen.
        if [ "$waited" -ge 120 ]; then
            echo "[switchwall] gave up waiting for $dir, proceeding unserialised" >&2
            return 1
        fi
        sleep 0.5
    done
    printf -v "$var" '%d' 1
    trap switchwall_release_lock EXIT
    return 0
}

switchwall_acquire_lock() {
    switchwall_take_lock "$SWITCHWALL_LOCK" SWITCHWALL_LOCK_TAKEN
}

switchwall_acquire_colors_lock() {
    switchwall_take_lock "$COLORS_LOCK" COLORS_LOCK_TAKEN
}

# True when the wallpaper player already plays exactly $1.
#
# The picker previews a clip by handing the running player the very file an
# apply would use. Rebuilding the player for a wallpaper that is already on
# screen is a visible reload of the desktop for nothing, so the apply keeps
# it instead — but only after reading the path back over the IPC socket, so a
# stale "we handed it over" claim can never leave the wrong clip running.
player_plays() {
    local want="$1" sock="" reply="" got=""
    command -v python3 >/dev/null 2>&1 || return 1
    for sock in "${MPV_SOCKET_PREFIX}"*.sock; do
        [[ -S "$sock" ]] || continue
        reply="$(python3 -c 'import socket, sys
sk = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sk.settimeout(2)
try:
    sk.connect(sys.argv[1])
    sk.sendall(b"{\"command\":[\"get_property\",\"path\"]}\n")
    sys.stdout.write(sk.recv(65536).decode())
except Exception:
    pass' "$sock" 2>/dev/null | head -n1)"
        got="$(printf '%s' "$reply" | sed -n 's/.*"data":"\([^"]*\)".*/\1/p')"
        [[ -n "$got" && "$got" == "$want" ]] && return 0
    done
    return 1
}

# Deploys the video wallpaper supervisor.
#
# The supervisor owns the mpvpaper process, the proxy encoding and the
# session re-derivation. It lives next to the restore script in the user's
# own custom directory, so it is installed from the shell's script directory.
install_video_wallpaper_supervisor() {
    local src="$SCRIPT_DIR/../wallpapers/__video_wallpaper.sh"
    [[ -f "$src" ]] || return 1
    mkdir -p "$RESTORE_SCRIPT_DIR" || return 1
    # The copy this shell ships (kept in sync with the checkout) is the
    # canonical one: the deployed copy in the live-only custom/ dir is
    # refreshed whenever they differ, so new flags (--prefetch) and fixes
    # actually reach the script that runs the supervisor. Atomic replace;
    # a running supervisor keeps its already-loaded copy.
    if cmp -s "$src" "$VIDEO_WALLPAPER_SCRIPT" 2>/dev/null; then
        return 0
    fi
    install -m 755 "$src" "$VIDEO_WALLPAPER_SCRIPT.tmp" 2>/dev/null &&
        mv -f "$VIDEO_WALLPAPER_SCRIPT.tmp" "$VIDEO_WALLPAPER_SCRIPT" || return 1
    return 0
}

# The compositor is not always running: the greeter, a systemd unit or a
# plain shell have no monitors to query. The queries have to fail softly.
monitor_value() {
    local query="$1"
    local default="$2"
    local out=""
    if command -v hyprctl >/dev/null 2>&1; then
        out=$(hyprctl monitors -j 2>/dev/null | jq "$query" 2>/dev/null | xargs)
    fi
    [[ -n "$out" && "$out" != "null" ]] || out="$default"
    printf '%s' "$out"
}

kill_existing_mpvpaper() {
    # The video wallpaper is supervised: the supervisor owns the mpvpaper
    # process, the proxy encoding and the session re-derivation, so it has to
    # be stopped through it.
    if [[ -x "$VIDEO_WALLPAPER_SCRIPT" ]]; then
        "$VIDEO_WALLPAPER_SCRIPT" --stop 2>/dev/null || true
    else
        pkill -f -9 mpvpaper || true
    fi
}

start_video_wallpaper() {
    local video="$1"
    # Make sure the supervisor on disk is the one this shell ships: an older
    # one passes the mpv options with -o and makes mpvpaper crash.
    install_video_wallpaper_supervisor || true
    if [[ -x "$VIDEO_WALLPAPER_SCRIPT" ]]; then
        "$VIDEO_WALLPAPER_SCRIPT" "$video" || true
        return
    fi
    # Fallback without the supervisor: one mpvpaper per monitor.
    local monitors monitor conf_dir
    monitors=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | .name')
    rm -f "$MPV_SOCKET_PREFIX"*.sock
    for monitor in $monitors; do
        conf_dir="$MPV_CONF_ROOT/$monitor"
        write_mpv_conf "$conf_dir" "$MPV_SOCKET_PREFIX$monitor.sock" || continue
        XDG_CONFIG_HOME="$conf_dir" mpvpaper $MPVPAPER_FLAGS "$monitor" "$video" &
        sleep 0.1
    done
}

# Renders the preview image of a video wallpaper.
#
# The first frame of a clip is usually black (fade in) and would look like a
# broken preview, so a frame a few seconds in is used. When even that fails,
# the last preview that worked is reused, and as a last resort a flat image
# is written: the preview must never be empty.
generate_video_thumbnail() {
    local video="$1"
    local out="$2"

    for seek in 00:00:03 00:00:01 00:00:00; do
        ffmpeg -y -ss "$seek" -i "$video" -frames:v 1 \
            -vf "scale=1280:1280:force_original_aspect_ratio=decrease" \
            "$out" >/dev/null 2>&1
        if [[ -s "$out" ]]; then
            cp -f "$out" "$LAST_THUMBNAIL" 2>/dev/null || true
            return 0
        fi
    done

    if [[ -s "$LAST_THUMBNAIL" ]]; then
        cp -f "$LAST_THUMBNAIL" "$out" 2>/dev/null || true
        return 0
    fi

    magick -size 64x64 "xc:#202020" "$out" >/dev/null 2>&1
    [[ -s "$out" ]]
}

create_restore_script() {
    # The wallpaper is resolved from the shell config when the script runs, so
    # no path is baked in and the script stays valid when the wallpaper
    # changes.
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: $(date)

set -u
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="\${XDG_CONFIG_HOME:-\$HOME/.config}/illogical-impulse/config.json"

wallpaper=""
if [[ -f "\$CONFIG_FILE" ]]; then
    wallpaper=\$(jq -r '.background.wallpaperPath // ""' "\$CONFIG_FILE" 2>/dev/null)
    # The shell decodes video wallpapers itself in this mode; starting
    # mpvpaper here would race the shell and double-decode every clip.
    if [[ "\$(jq -r '.background.inShellVideo // true' "\$CONFIG_FILE" 2>/dev/null)" == "true" ]]; then
        exit 0
    fi
fi

if [[ -z "\$wallpaper" || ! -f "\$wallpaper" ]]; then
    exit 0
fi

# The supervisor is optional: it is only installed when the user deployed
# it. Without it the wallpaper is started directly, one mpvpaper per
# monitor, so the restore always works on its own.
if [[ -x "\$SCRIPT_DIR/__video_wallpaper.sh" ]]; then
    exec "\$SCRIPT_DIR/__video_wallpaper.sh" "\$wallpaper"
fi

case "\$wallpaper" in
    *.mp4|*.webm|*.mkv|*.avi|*.mov|*.gif|*.m4v|*.wmv|*.flv|*.ogv|*.3gp|*.qt) ;;
    *) exit 0 ;;
esac

pkill -f -9 mpvpaper 2>/dev/null || true
rm -f "$MPV_SOCKET_PREFIX"*.sock

# mpvpaper's -o option writes to /tmp/mpvpaper_<pid>.config with an unchecked
# fopen(). When /tmp is not writable by the user, mpvpaper segfaults on
# startup, so the options are passed through a private mpv configuration
# directory instead: mpv reads \$XDG_CONFIG_HOME/mpv/mpv.conf.
MPV_CONF_ROOT="$MPV_CONF_ROOT"

write_mpv_conf() {
    local dir="\$1"
    local socket="\$2"
    mkdir -p "\$dir/mpv" || return 1
    {
        printf '%s\n' "no-audio" "loop=inf" "hwdec=auto" "scale=bilinear"
        printf '%s\n' "interpolation=no" "video-sync=display-resample"
        printf '%s\n' "panscan=1.0" "video-scale-x=1.0" "video-scale-y=1.0"
        printf '%s\n' "video-align-x=0.5" "video-align-y=0.5" "load-scripts=no"
        printf 'input-ipc-server=%s\n' "\$socket"
    } >"\$dir/mpv/mpv.conf" || return 1
    return 0
}

if command -v hyprctl >/dev/null 2>&1; then
    for monitor in \$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | .name'); do
        conf_dir="\$MPV_CONF_ROOT/\$monitor"
        write_mpv_conf "\$conf_dir" "$MPV_SOCKET_PREFIX\$monitor.sock" || continue
        XDG_CONFIG_HOME="\$conf_dir" mpvpaper $MPVPAPER_FLAGS "\$monitor" "\$wallpaper" &
        sleep 0.1
    done
fi
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

remove_restore() {
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# The content of this script will be generated by switchwall.sh - Don't modify it by yourself.
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
}

set_wallpaper_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        config_json_update "$SHELL_CONFIG_FILE" --arg path "$path" '.background.wallpaperPath = $path'
    fi
}

set_thumbnail_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        config_json_update "$SHELL_CONFIG_FILE" --arg path "$path" '.background.thumbnailPath = $path'
    fi
}

categorize_wallpaper() {
    img_cat=$("$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh" "$1")
    echo "$img_cat" > "$STATE_DIR/user/generated/wallpaper/category.txt"
}

switch() {
    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"
    colors_only_flag="$6"
    colors_lock_flag="$7"
    # The file the picker's preview already handed to the running player. When
    # the player is confirmed to be on it, this apply adopts that player
    # instead of rebuilding it (keep_player below).
    keep_player_file="${8:-}"

    # One run at a time, and a clip that is already applied and playing has
    # nothing to rebuild. The picker fires a second apply while the first is
    # still encoding a brand-new clip (nothing seemed to happen), and the two
    # runs then killed and rebuilt each other's player — that is the wallpaper
    # visibly reapplying a while later.
    switchwall_acquire_lock

    # In-shell mode: the shell owns the video. Stop any player/supervisor left
    # over from the old setup before touching the wallpaper, then never start a
    # new one below.
    if [[ "$IN_SHELL_VIDEO" == "true" ]]; then
        "$VIDEO_WALLPAPER_SCRIPT" --stop >/dev/null 2>&1 || true
    fi

    if [[ "$IN_SHELL_VIDEO" != "true" ]]; then
        install_video_wallpaper_supervisor || true
    fi
    if [[ "$IN_SHELL_VIDEO" != "true" && -z "$colors_only_flag" ]] && is_video "$imgpath" \
        && [[ "$imgpath" == "$(jq -r '.background.wallpaperPath // ""' "$SHELL_CONFIG_FILE" 2>/dev/null)" ]]; then
        local already=""
        already="$("$VIDEO_WALLPAPER_SCRIPT" --prefetch "$imgpath" 2>/dev/null)" || already=""
        if [[ -n "$already" ]] && player_plays "$already"; then
            echo "[switchwall] $imgpath is already applied and playing; nothing to do"
            return 0
        fi
    fi

    aiStylingEnabled=$(jq -r '.background.widgets.clock.cookie.aiStyling' "$SHELL_CONFIG_FILE")
    if [[ "$aiStylingEnabled" == "true" && -z "$colors_only_flag" ]]; then
        categorize_wallpaper "$imgpath" &
    fi

    read scale screenx screeny screensizey < <(hyprctl monitors -j 2>/dev/null | jq '.[] | select(.focused) | .scale, .x, .y, .height' 2>/dev/null | xargs)
    scale="${scale:-1}"
    screenx="${screenx:-0}"
    screeny="${screeny:-0}"
    screensizey="${screensizey:-1080}"
    cursorposx=$(hyprctl cursorpos -j 2>/dev/null | jq '.x' 2>/dev/null) || cursorposx=960
    cursorposx=$(bc <<< "scale=0; ($cursorposx - $screenx) * $scale / 1")
    cursorposy=$(hyprctl cursorpos -j 2>/dev/null | jq '.y' 2>/dev/null) || cursorposy=540
    cursorposy=$(bc <<< "scale=0; ($cursorposy - $screeny) * $scale / 1")
    cursorposy_inverted=$((screensizey - cursorposy))

    matugen_args=(--source-color-index 0)

    if [[ "$color_flag" == "1" ]]; then
        matugen_args+=(color hex "$color")
        generate_colors_material_args=(--color "$color")
    else
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        check_and_prompt_upscale "$imgpath" &

        # A colors-only run must not touch a healthy player: --noswitch
        # callers only regenerate colours. A dead player (no IPC socket) is
        # still brought back up, so a crashed wallpaper never stays black
        # after a colour regeneration.
        colors_only_restart=0
        if [[ "$IN_SHELL_VIDEO" != "true" && -n "$colors_only_flag" ]] && is_video "$imgpath" \
            && ! compgen -G "${MPV_SOCKET_PREFIX}*.sock" > /dev/null; then
            colors_only_restart=1
        fi

        # Record the wallpaper BEFORE the player is touched. The shell reads
        # background.wallpaperPath to decide what the desktop shows, so it must
        # never lag behind what the player was just handed — and waiting for the
        # encode used to make the first apply of a brand-new clip look like it
        # had not been applied at all.
        if [[ -z "$colors_only_flag" ]]; then
            set_wallpaper_path "$imgpath"
        fi

        # What the running player needs, if anything:
        #   keep     — already on this file (a preview adopted it)
        #   handoff  — alive but on another file: loadfile, no teardown
        #   rebuild  — nothing reachable: kill and start, as before
        # The handoff is what makes an apply instant. Rebuilding mpvpaper
        # leaves ~3 seconds with no player at all, and that hole is exactly
        # the "it is applied but not playing" a double-click shows; the
        # picker's preview already proved loadfile switches clips cleanly.
        local player_action="rebuild"
        if [[ "$IN_SHELL_VIDEO" != "true" && -z "$colors_only_flag" ]] && is_video "$imgpath"; then
            install_video_wallpaper_supervisor || true
            local want=""
            want="$("$VIDEO_WALLPAPER_SCRIPT" --prefetch "$imgpath" 2>/dev/null)" || want=""
            if [[ -n "$want" ]]; then
                if player_plays "$want"; then
                    player_action="keep"
                elif player_loadfile "$want"; then
                    player_action="handoff"
                fi
            fi
        fi

        if [[ -z "$colors_only_flag" || "$colors_only_restart" -eq 1 ]]; then
            if [[ "$player_action" == "rebuild" ]]; then
                # Build the proxy BEFORE the current player dies: the old
                # wallpaper keeps playing while ffmpeg works instead of leaving
                # a frozen desktop for the whole encode (choosing an uncached
                # video used to freeze until the proxy finished). Cached
                # proxies return instantly, so the common case is unchanged.
                # The deployed copy must be refreshed first: it lives in the
                # live-only custom/ dir, so checkout changes (like --prefetch)
                # only reach it through the installer.
                if is_video "$imgpath"; then
                    if [[ "$IN_SHELL_VIDEO" != "true" ]]; then
                        install_video_wallpaper_supervisor || true
                    fi
                    if [[ -x "$VIDEO_WALLPAPER_SCRIPT" ]]; then
                        "$VIDEO_WALLPAPER_SCRIPT" --prefetch "$imgpath" >/dev/null || true
                    fi
                fi
                if [[ "$IN_SHELL_VIDEO" != "true" ]]; then
                    kill_existing_mpvpaper
                fi
            fi
        fi

        if is_video "$imgpath"; then
            mkdir -p "$THUMBNAIL_DIR"

            missing_deps=()
            if [[ "$IN_SHELL_VIDEO" != "true" ]] && ! command -v mpvpaper &> /dev/null; then
                missing_deps+=("mpvpaper")
            fi
            if ! command -v ffmpeg &> /dev/null; then
                missing_deps+=("ffmpeg")
            fi
            if [ ${#missing_deps[@]} -gt 0 ]; then
                echo "Missing deps: ${missing_deps[*]}"
                echo "Arch: sudo pacman -S ${missing_deps[*]}"
                action=$(notify-send \
                    -a "Wallpaper switcher" \
                    -c "im.error" \
                    -A "install_arch=Install (Arch)" \
                    "Can't switch to video wallpaper" \
                    "Missing dependencies: ${missing_deps[*]}")
                if [[ "$action" == "install_arch" ]]; then
                    kitty -1 sudo pacman -S "${missing_deps[*]}"
                    if [[ "$IN_SHELL_VIDEO" == "true" ]] && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    elif command -v mpvpaper &>/dev/null && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    fi
                fi
                exit 0
            fi

            if [[ -z "$colors_only_flag" || "$colors_only_restart" -eq 1 ]]; then
                if [[ -n "$colors_only_flag" ]]; then
                    # A colours-only run that found the player dead still has to
                    # record the wallpaper it is about to restart; a normal
                    # apply recorded it before touching the player.
                    set_wallpaper_path "$imgpath"
                fi
                # keep/handoff: the player already has this clip, or was just
                # handed it, so only the config catches up — no kill, no
                # restart, no three-second hole with no wallpaper. In-shell
                # mode never starts a player at all.
                if [[ "$IN_SHELL_VIDEO" != "true" && "$player_action" == "rebuild" ]]; then
                    start_video_wallpaper "$imgpath"
                fi
            fi

            thumbnail="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
            generate_video_thumbnail "$imgpath" "$thumbnail"

            if [[ -z "$colors_only_flag" ]]; then
                set_thumbnail_path "$thumbnail"
            fi

            if [[ -s "$thumbnail" ]]; then
                matugen_args+=(image "$thumbnail")
                generate_colors_material_args=(--path "$thumbnail")
                if [[ -z "$colors_only_flag" ]]; then
                    create_restore_script
                fi
            else
                echo "Cannot create image to colorgen"
                if [[ -z "$colors_only_flag" ]]; then
                    remove_restore
                fi
                exit 1
            fi
        else
            matugen_args+=(image "$imgpath")
            generate_colors_material_args=(--path "$imgpath")
            if [[ -z "$colors_only_flag" ]]; then
                set_wallpaper_path "$imgpath"
                # The preview of a still wallpaper is the wallpaper itself, so
                # the thumbnail never points at a stale video frame.
                set_thumbnail_path "$imgpath"
                remove_restore
            fi
        fi
    fi

    # Phase 1 is done: the wallpaper is recorded, the poster is written and the
    # player has been switched. Let go of the run lock HERE — colour
    # generation is the slow part and must not keep the next apply waiting,
    # while colours themselves stay serialised on their own lock.
    switchwall_release_lock
    switchwall_acquire_colors_lock

    if [[ -z "$mode_flag" ]]; then
        current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        if [[ "$current_mode" == "prefer-dark" ]]; then
            mode_flag="dark"
        else
            mode_flag="light"
        fi
    fi

    if [[ -n "$mode_flag" ]]; then
        matugen_args+=(--mode "$mode_flag")
        if [[ $(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode' "$SHELL_CONFIG_FILE") == "true" ]]; then
            generate_colors_material_args+=(--mode "dark")
        else
            generate_colors_material_args+=(--mode "$mode_flag")
        fi
    fi
    [[ -n "$type_flag" ]] && matugen_args+=(--type "$type_flag") && generate_colors_material_args+=(--scheme "$type_flag")
    generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)
    generate_colors_material_args+=(--cache "$STATE_DIR/user/generated/color.txt")

    if [[ -n "$named_scheme" && -z "$noswitch_flag" && -z "$colors_lock_flag" ]]; then
        return
    fi

    pre_process "$mode_flag"

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
        if [ "$enable_apps_shell" == "false" ]; then
            echo "App and shell theming disabled, skipping matugen and color generation"
            return
        fi
    fi

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
        harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
        term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
        [[ "$harmony" != "null" && -n "$harmony" ]] && generate_colors_material_args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && generate_colors_material_args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && generate_colors_material_args+=(--term_fg_boost "$term_fg_boost")
    fi

    colors_json_path="$STATE_DIR/user/generated/colors.json"
    if [[ -n "$named_scheme" && -z "$colors_lock_flag" ]]; then
        apply_named_scheme "$mode_flag" "$imgpath"
        return
    fi

    colors_lock_json_path="$STATE_DIR/user/generated/colors-lock.json"
    colors_lock_watch_paths=(
        "$colors_json_path"
        "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
        "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"
        "$XDG_CONFIG_HOME/hypr/hyprland/colors.lua"
    )
    colors_lock_backups=()
    if [[ -n "$colors_lock_flag" ]]; then
        for i in "${!colors_lock_watch_paths[@]}"; do
            watch_path="${colors_lock_watch_paths[$i]}"
            if [[ -f "$watch_path" ]]; then
                backup_path="$(mktemp)"
                cp "$watch_path" "$backup_path"
                colors_lock_backups[$i]="$backup_path"
            fi
        done
    fi

    matugen "${matugen_args[@]}"

    if [[ -z "$colors_lock_flag" ]]; then
        # matugen rewrites ~/.config/hypr/hyprland/colors.lua atomically, and
        # Hyprland's config watcher only reacts to IN_CLOSE_WRITE, so the new
        # palette stays invisible until the compositor re-reads its config.
        hyprctl reload >/dev/null 2>&1 || true
    fi

    if [[ -n "$colors_lock_flag" ]]; then
        if [[ -f "$colors_json_path" ]]; then
            cp "$colors_json_path" "$colors_lock_json_path"
        fi
        for i in "${!colors_lock_watch_paths[@]}"; do
            watch_path="${colors_lock_watch_paths[$i]}"
            backup_path="${colors_lock_backups[$i]:-}"
            if [[ -n "$backup_path" ]]; then
                mv "$backup_path" "$watch_path"
            fi
        done
    fi

    source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"

    if [[ -n "$colors_lock_flag" ]]; then
        output_scss="$STATE_DIR/user/generated/material_colors_lock.scss"
    else
        output_scss="$STATE_DIR/user/generated/material_colors.scss"
    fi

    python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" \
        > "$output_scss"
    deactivate

    if [[ -z "$colors_lock_flag" ]]; then
        "$SCRIPT_DIR"/applycolor.sh
        update_icon_scheme "$mode_flag"
    fi

    max_width_desired="$(monitor_value '([.[].width] | min)' 1920)"
    max_height_desired="$(monitor_value '([.[].height] | min)' 1080)"
    post_process "$max_width_desired" "$max_height_desired" "$imgpath" "$colors_lock_flag"
}

main() {
    imgpath=""
    mode_flag=""
    type_flag=""
    color_flag=""
    color=""
    noswitch_flag=""
    colors_only_flag=""
    colors_lock_flag=""
    explicit_image=""
    start_dir_flag=""
    keep_player_file=""

    get_type_from_config() {
        jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
    }
    get_named_scheme_from_config() {
        jq -r '.appearance.palette.namedScheme // ""' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
    }
    set_named_scheme() {
        local previous
        previous="$(get_named_scheme_from_config)"
        if [[ "$previous" != "$1" ]]; then
            config_json_update "$SHELL_CONFIG_FILE" --arg name "$1" \
                '.appearance.palette.namedScheme = $name | .appearance.palette.namedSchemePrimary = "" | .appearance.palette.namedSchemeSecondary = ""'
        fi
    }
    set_named_accent() {
        local slot="$1" value="$2"
        [[ "$value" == "clear" ]] && value=""
        config_json_update "$SHELL_CONFIG_FILE" --arg slot "$slot" --arg value "$value" \
            '.appearance.palette["namedScheme" + $slot] = $value'
    }
    get_named_accent_from_config() {
        jq -r --arg key "namedScheme$1" '.appearance.palette[$key] // ""' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
    }
    get_accent_color_from_config() {
        jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
    }
    set_accent_color() {
        local color="$1"
        config_json_update "$SHELL_CONFIG_FILE" --arg color "$color" '.appearance.palette.accentColor = $color'
    }

    detect_scheme_type_from_image() {
        local img="$1"
        source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
        "$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n'
        deactivate
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                mode_flag="$2"
                shift 2
                ;;
            --type)
                type_flag="$2"
                shift 2
                ;;
            --color)
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    set_accent_color "$2"
                    shift 2
                elif [[ "$2" == "clear" ]]; then
                    set_accent_color ""
                    shift 2
                else
                    set_accent_color $(hyprpicker --no-fancy)
                    shift
                fi
                ;;
            --scheme-name)
                if [[ "$2" == "clear" ]]; then
                    set_named_scheme ""
                else
                    set_named_scheme "$2"
                fi
                shift 2
                ;;
            --scheme-primary)
                set_named_accent Primary "$2"
                shift 2
                ;;
            --scheme-secondary)
                set_named_accent Secondary "$2"
                shift 2
                ;;
            --image)
                imgpath="$2"
                explicit_image="1"
                shift 2
                ;;
            --start-dir)
                start_dir_flag="$2"
                shift 2
                ;;
            --keep-player)
                # The file the preview already gave the player: keep it if it
                # is still the one playing, instead of rebuilding it.
                keep_player_file="$2"
                shift 2
                ;;
            --noswitch)
                noswitch_flag="1"
                if [[ -z "$imgpath" ]]; then
                    imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                fi
                shift
                ;;
            --colors_lock)
                colors_lock_flag="1"
                colors_only_flag="1"
                noswitch_flag="1"
                if [[ -z "$imgpath" ]]; then
                    imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                fi
                shift
                ;;
            *)
                if [[ -z "$imgpath" ]]; then
                    imgpath="$1"
                fi
                shift
                ;;
        esac
    done

    # A run that is not switching the wallpaper must never touch a healthy
    # player: every --noswitch caller (the settings opening, palette and
    # mode changes) used to kill and restart the wallpaper here even though
    # the file never changed — that is why opening settings reloaded the
    # desktop video. A dead player is still brought back up inside switch().
    if [[ -n "$noswitch_flag" ]]; then
        colors_only_flag="1"
    fi

    named_scheme="$(get_named_scheme_from_config)"
    if [[ -n "$named_scheme" && ! -f "$SCRIPT_DIR/schemes/$named_scheme.json" && ! -f "$(dirname "$SHELL_CONFIG_FILE")/schemes/$named_scheme.json" ]]; then
        echo "[switchwall.sh] Warning: Unknown named scheme '$named_scheme', ignoring" >&2
        named_scheme=""
    fi

    named_primary="$(get_named_accent_from_config Primary)"
    named_secondary="$(get_named_accent_from_config Secondary)"

    config_color="$(get_accent_color_from_config)"
    if [[ "$config_color" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
        color_flag="1"
        color="$config_color"
    fi

    if [[ -z "$type_flag" ]]; then
        type_flag="$(get_type_from_config)"
    fi

    allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot auto)
    valid_type=0
    for t in "${allowed_types[@]}"; do
        if [[ "$type_flag" == "$t" ]]; then
            valid_type=1
            break
        fi
    done
    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi

    # Only prompt for wallpaper if not using --color and not using --noswitch and no imgpath set
    if [[ -z "$imgpath" && -z "$color_flag" && -z "$noswitch_flag" ]]; then
        if [[ -n "$start_dir_flag" && -d "$start_dir_flag" ]]; then
            cd "$start_dir_flag" || return 1
        else
            cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null || cd "$(xdg-user-dir PICTURES)" || return 1
        fi
        imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
    fi

    if [[ -n "$imgpath" && -z "$noswitch_flag" ]]; then
        set_accent_color ""
        color_flag=""
        color=""
    fi

    if [[ "$type_flag" == "auto" ]]; then
        if [[ -n "$imgpath" && -f "$imgpath" ]]; then
            detected_type="$(detect_scheme_type_from_image "$imgpath")"
            valid_detected=0
            for t in "${allowed_types[@]}"; do
                if [[ "$detected_type" == "$t" && "$detected_type" != "auto" ]]; then
                    valid_detected=1
                    break
                fi
            done
            if [[ $valid_detected -eq 1 ]]; then
                type_flag="$detected_type"
            else
                echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
                type_flag="scheme-tonal-spot"
            fi
        else
            echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    if [[ "$mode_flag" == "dark" || "$mode_flag" == "light" ]]; then
        local imgdir="$(dirname "$imgpath")"
        local imgbase="$(basename "$imgpath")"
        local imgname="${imgbase%.*}"
        local imgext="${imgbase##*.}"

        local stripped_name="${imgname%-dark}"
        stripped_name="${stripped_name%-light}"

        local new_imgpath="${imgdir}/${stripped_name}-${mode_flag}.${imgext}"
        local new_stripped_imgpath="${imgdir}/${stripped_name}.${imgext}"

        if [[ -f "$new_imgpath" ]]; then
            imgpath="$new_imgpath"
        elif [[ -f "$new_stripped_imgpath" ]]; then
            imgpath="$new_stripped_imgpath"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color" "$colors_only_flag" "$colors_lock_flag" "$keep_player_file"
}

main "$@"