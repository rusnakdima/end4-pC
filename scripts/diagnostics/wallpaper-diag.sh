#!/usr/bin/env bash
# One-shot snapshot of the wallpaper pipeline. Run this when a wallpaper looks
# stuck and paste the output: it separates "the player never started" from
# "the player runs but is not revealed", and measures whether anything is
# actually moving on screen.
#
#   ~/.config/quickshell/end4-pC/scripts/diagnostics/wallpaper-diag.sh
set -u

export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t /run/user/1000/hypr/ 2>/dev/null | head -1)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
LOG="$HOME/.config/hypr/custom/scripts/.video_wallpaper.log"
PROXY_DIR="$HOME/.config/hypr/custom/scripts/mpvpaper_proxies"
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

socket_path() {
    local s; s="$(ls "$XDG_RUNTIME_DIR"/mpvpaper-*.sock 2>/dev/null | head -1)"
    [ -n "$s" ] || { echo "(no socket)"; return; }
    python3 -c 'import socket,sys
sk=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); sk.settimeout(2)
try:
    sk.connect(sys.argv[1]); sk.sendall(b"{\"command\":[\"get_property\",\"path\"]}\n"); sys.stdout.write(sk.recv(65536).decode())
except Exception as e:
    print("connect failed:", e)' "$s" 2>/dev/null \
        | sed -n 's/.*"data":"\([^"]*\)".*/\1/p; s/.*connect failed.*/&/p'
}

echo "=== 1. configured wallpaper ==="
wp="$(jq -r '.background.wallpaperPath // ""' "$CFG" 2>/dev/null)"
th="$(jq -r '.background.thumbnailPath // ""' "$CFG" 2>/dev/null)"
echo "wallpaperPath : $wp"
echo "  exists      : $([ -f "$wp" ] && echo yes || echo 'NO — FILE MISSING')"
echo "is video      : $(case "$wp" in *.mp4|*.webm|*.mkv|*.mov|*.m4v) echo yes;; *) echo no;; esac)"
echo "thumbnailPath : $th"
echo "  exists      : $([ -f "$th" ] && echo yes || echo no)"

echo
echo "=== 2. shell view (IPC) ==="
if command -v qs >/dev/null 2>&1; then
    echo -n "wallpapers    : "; qs -c end4-pC ipc call wallpapers status 2>&1
    echo -n "livewallpaper : "; qs -c end4-pC ipc call livewallpaper status 2>&1
else
    echo "(qs not on PATH)"
fi

echo
echo "=== 3. player processes ==="
echo "mpvpaper      : $(pgrep -a -x mpvpaper || echo NONE)"
echo "supervisor    : $(pgrep -af 'video_wallpaper[.]sh --supervise' | grep -v 'bash -c' || echo NONE)"
echo "ffmpeg        : $(pgrep -a -x ffmpeg || echo NONE)"
echo "switchwall    : $(pgrep -af 'colors/switchwa[a]ll.sh' | grep -v 'bash -c' || echo NONE)"
echo "socket files  : $(ls -la "$XDG_RUNTIME_DIR"/mpvpaper-*.sock 2>/dev/null || echo NONE)"
echo "socket says   : $(socket_path)"
echo "lock dirs     : $([ -d "$XDG_RUNTIME_DIR/switchwall.lock.d" ] && echo phase1-HELD || echo phase1-free) $([ -d "$XDG_RUNTIME_DIR/switchwall.colors.lock.d" ] && echo colors-HELD || echo colors-free)"
echo "pidfiles      : $(cat "$HOME/.config/hypr/custom/scripts/.video_wallpaper.pid" 2>/dev/null || echo '-'), $(cat "$HOME/.config/hypr/custom/scripts/.video_wallpaper.mpvpaper.pid" 2>/dev/null || echo '-')"

echo
echo "=== 4. is anything MOVING on screen? ==="
if command -v grim >/dev/null 2>&1 && command -v magick >/dev/null 2>&1; then
    grim "$D/1.png"; sleep 2.5; grim "$D/2.png"
    n=$(magick compare -metric AE "$D/1.png" "$D/2.png" null: 2>&1 || true)
    echo "pixels changed over 2.5s: ${n:-0}"
    echo "  (a live wallpaper is normally 100000+; a static poster is a few thousand)"
else
    echo "(grim/magick unavailable)"
fi

echo
echo "=== 5. last log lines (mpv status lines stripped) ==="
grep -vE "^V: |^\(Paused\)" "$LOG" 2>/dev/null | tail -15 || echo "(no log)"
echo
echo "=== 6. proxy cache for this wallpaper ==="
b="$(basename "${wp%.*}" 2>/dev/null)"
ls -la "$PROXY_DIR"/"$b"-* 2>/dev/null || echo "(no proxy for it)"
