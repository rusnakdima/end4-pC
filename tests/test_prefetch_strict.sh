#!/usr/bin/env bash
# Checks the strict --prefetch contract: when a proxy is required and cannot
# be built, nothing is printed (so the caller shows a still instead of handing
# mpvpaper a raw source that freezes the compositor).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/wallpapers/__video_wallpaper.sh"
fail=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BROKEN="$WORK/not-a-real-video.mp4"
printf 'this is not a video at all\n' >"$BROKEN"

echo "test: strict prefetch of an unplayable source prints nothing"
out="$("$SCRIPT" --prefetch "$BROKEN" 2>/dev/null)"
rc=$?
if [[ -n "$out" ]]; then
    echo "FAIL: strict prefetch printed '$out'"; fail=1
else
    echo "  OK   printed nothing (rc=$rc)"
fi
if [[ $rc -eq 0 ]]; then
    echo "FAIL: strict prefetch exited 0 on failure"; fail=1
else
    echo "  OK   exited non-zero"
fi

echo "test: a light source still passes through untouched"
LIGHT="$WORK/light.mp4"
ffmpeg -y -v error -f lavfi -i "testsrc2=duration=1:size=640x360:rate=10" -c:v libx264 -pix_fmt yuv420p "$LIGHT" || {
    echo "FAIL: could not build synthetic source"; exit 1;
}
out3="$("$SCRIPT" --prefetch "$LIGHT" 2>/dev/null)"
if [[ "$out3" == "$LIGHT" ]]; then
    echo "  OK   light source returned as-is"
else
    echo "FAIL: light source got '$out3'"; fail=1
fi

if [[ $fail -eq 0 ]]; then
    echo "PASS: strict prefetch contract"
    exit 0
fi
exit 1
