#!/usr/bin/env bash
# Records every change in the wallpaper pipeline while you click.
#
#   ~/.config/quickshell/end4-pC/scripts/diagnostics/wallpaper-trace.sh [seconds]
#
# Start it FIRST, then reproduce the problem in the picker (set an image, then
# click a video, then click it again), and paste what it printed. A line shows
# whenever anything changes; it separates "the click never became a preview"
# (previewPath stays empty) from "the preview ran but no player started" from
# "the player started and was stopped again".
set -u
SECS="${1:-60}"

export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t /run/user/1000/hypr/ 2>/dev/null | head -1)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
QS=(qs -c end4-pC)
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
T0=$(date +%s%3N)

base(){ basename "${1:-}" 2>/dev/null | cut -c1-26; }
lval(){ "${QS[@]}" ipc call livewallpaper status 2>/dev/null | sed -n "s/.*\"$1\":\([^,}]*\).*/\1/p" | tr -d '" '; }
wval(){ "${QS[@]}" ipc call wallpapers status 2>/dev/null | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
playing(){
    local s; s="$(ls ${XDG_RUNTIME_DIR}/mpvpaper-*.sock 2>/dev/null | head -1)"
    [[ -n "$s" ]] || { echo "-"; return; }
    python3 -c 'import socket,sys
sk=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); sk.settimeout(1.5)
try:
    sk.connect(sys.argv[1]); sk.sendall(b"{\"command\":[\"get_property\",\"path\"]}\n"); sys.stdout.write(sk.recv(65536).decode())
except Exception: pass' "$s" 2>/dev/null | sed -n 's/.*"data":"\([^"]*\)".*/\1/p' | sed 's#.*/mpvpaper_proxies/##' | cut -c1-26
}
snapshot(){
    printf 'previewPath=%-26s confirmed=%-26s previewing=%-5s active=%-5s avail=%-5s mpv=%-3s sup=%-3s playing=%-26s config=%s' \
        "$(base "$(wval previewPath)")" "$(base "$(wval confirmedPath)")" \
        "$(lval previewing)" "$(lval previewPlayerActive)" "$(lval available)" \
        "$(pgrep -x mpvpaper | wc -l)" "$(pgrep -f '__video_wallpaper[.]sh --supervise' | wc -l)" \
        "$(playing)" "$(base "$(jq -r '.background.wallpaperPath' "$CFG" 2>/dev/null)")"
}

echo "tracing for ${SECS}s — reproduce the problem NOW (image, then click a video, then again)"
echo "start: $(snapshot)"
prev=""
end=$(( $(date +%s) + SECS ))
while [ "$(date +%s)" -lt "$end" ]; do
    sleep 0.4
    cur="$(snapshot)"
    if [ "$cur" != "$prev" ]; then
        t=$(awk "BEGIN{printf \"%5.1f\", ($(date +%s%3N)-$T0)/1000}")
        echo "t=${t}s  $cur"
        prev="$cur"
    fi
done
echo "end:  $(snapshot)"
