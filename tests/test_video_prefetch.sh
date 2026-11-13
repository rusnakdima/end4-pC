#!/usr/bin/env bash
# Regression test for the wallpaper proxy prefetch contract (freeze fix).
#
#   __video_wallpaper.sh --prefetch <file>
#     - prints the file the player should be handed (proxy for heavy sources,
#       the source itself for light ones)
#     - builds the proxy into the SHARED cache (hypr custom dir), so preview
#       and apply reuse each other's work
#     - never starts or stops a player (the running wallpaper must survive
#       the whole build — choosing an uncached video used to freeze the
#       desktop for the encode)
#     - is idempotent: a second call reuses the cache and prints the same path
#
# Run:  bash tests/test_video_prefetch.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WALLPAPER_SCRIPT="$SCRIPT_DIR/scripts/wallpapers/__video_wallpaper.sh"
PROXY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/custom/scripts/mpvpaper_proxies"

fail=0
say() { printf '  %s\n' "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

command -v ffmpeg >/dev/null 2>&1 || { echo "SKIP: ffmpeg not installed"; exit 0; }
[[ -x "$WALLPAPER_SCRIPT" ]] || { echo "FAIL: $WALLPAPER_SCRIPT missing"; exit 1; }

# A deliberately oversized-per-pixel source so source_needs_proxy() is true:
# 2200x1240 > the 2134x1200 proxy target.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SRC="$WORK/prefetch-test-source.mp4"
ffmpeg -y -v error -f lavfi -i "testsrc2=duration=1:size=2200x1240:rate=30" -c:v libx264 -pix_fmt yuv420p "$SRC" \
    || { echo "FAIL: could not build synthetic source"; exit 1; }

players_before="$(pgrep -x mpvpaper | wc -l)"

echo "test: prefetch builds into the shared cache and stays off the player"
out1="$("$WALLPAPER_SCRIPT" --prefetch "$SRC" 2>/dev/null)"
players_after="$(pgrep -x mpvpaper | wc -l)"

[[ -n "$out1" ]] || die "prefetch printed nothing"
[[ -f "$out1" && -s "$out1" ]] || die "printed playfile does not exist: '$out1'"
case "$out1" in
    "$PROXY_DIR"/*) say "proxy landed in the shared cache: $(basename "$out1")" ;;
    *) die "proxy not in shared cache: $out1" ;;
esac
[[ "$players_before" == "$players_after" ]] \
    || die "prefetch changed the number of running players ($players_before -> $players_after)"

echo "test: second run is cached and idempotent"
t0=$SECONDS
out2="$("$WALLPAPER_SCRIPT" --prefetch "$SRC" 2>/dev/null)"
elapsed=$((SECONDS - t0))
[[ "$out1" == "$out2" ]] || die "cached run printed a different path"
[[ "$elapsed" -le 2 ]] || die "cached run took ${elapsed}s (expected instant)"

echo "test: a non-16:9 source keeps its aspect ratio and drops audio"
WIDE="$WORK/wide-with-audio.mp4"
ffmpeg -y -v error -f lavfi -i "testsrc2=duration=1:size=2200x900:rate=30" \
    -f lavfi -i "sine=frequency=440:duration=1" -shortest \
    -c:v libx264 -pix_fmt yuv420p -c:a aac "$WIDE" \
    || { echo "FAIL: could not build wide synthetic source"; exit 1; }
wide_out="$("$WALLPAPER_SCRIPT" --prefetch "$WIDE" 2>/dev/null)"
[[ -n "$wide_out" && -f "$wide_out" ]] || die "wide prefetch printed no file"
case "$wide_out" in
    "$PROXY_DIR"/*) say "wide proxy: $(basename "$wide_out")" ;;
    *) die "wide proxy not in shared cache: $wide_out" ;;
esac
read -r wide_w wide_h < <(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=p=0:s=, "$wide_out" | tr ',' ' ')
[[ -n "$wide_w" && -n "$wide_h" ]] || die "could not read wide proxy dimensions"
awk "BEGIN { exit !($wide_w / $wide_h > 2.3 && $wide_w / $wide_h < 2.6) }" \
    || die "wide proxy aspect not preserved: ${wide_w}x${wide_h}"
wide_audio="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$wide_out")"
[[ -z "$wide_audio" ]] || die "wide proxy still has audio: $wide_audio"

echo "test: a light source passes through untouched (no proxy)"
LIGHT="$WORK/light.mp4"
ffmpeg -y -v error -f lavfi -i "testsrc2=duration=1:size=640x360:rate=10" -c:v libx264 -pix_fmt yuv420p "$LIGHT"
out3="$("$WALLPAPER_SCRIPT" --prefetch "$LIGHT" 2>/dev/null)"
[[ "$out3" == "$LIGHT" ]] || die "light source should be played as-is, got: $out3"

# Cleanup the synthetic proxies so the real cache only holds real wallpapers.
rm -f "$out1" "$wide_out" 2>/dev/null

if [[ "$fail" -eq 0 ]]; then
    echo "PASS: prefetch contract (shared cache, player untouched, idempotent, aspect preserved, no audio, light passthrough)"
    exit 0
fi
exit 1
