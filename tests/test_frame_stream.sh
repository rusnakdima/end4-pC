#!/usr/bin/env bash
# frame_stream.py: produces frames at the target rate, and dies on SIGTERM
# (the picker stops the stream by killing it).
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
V="$HOME/Videos/Wallpapers/ye-shunguang-zenless-zone-zero-2-moewalls-com.mp4"
fail=0

echo "test: frame rate"
# -k 2: if it does not exit on TERM, force-kill after 2s so we never hang.
n=$(timeout -k 2 5 python3 scripts/wallpapers/frame_stream.py "$V" 2>/dev/null | wc -l)
echo "  $n frames in ~5s (expect roughly 80-100 at 20 fps)"
if [ "$n" -lt 40 ]; then
    echo "  FAIL: too few frames"; fail=1
else
    echo "  OK"
fi

echo "test: SIGTERM stops it (and its ffmpeg)"
python3 scripts/wallpapers/frame_stream.py "$V" >/tmp/opencode/fs_test.out 2>/dev/null &
pid=$!
sleep 2
kill -TERM "$pid" 2>/dev/null
# The handler waits up to 2s for ffmpeg to actually exit before python
# returns, so give it that long before judging.
sleep 3
if kill -0 "$pid" 2>/dev/null; then
    echo "  FAIL: python still alive after SIGTERM"
    kill -9 "$pid" 2>/dev/null
    fail=1
else
    echo "  OK: python exited"
fi
leftovers=$(pgrep -f "[s]cale=480:480" | wc -l)
echo "  leftover ffmpeg: $leftovers"
if [ "$leftovers" -gt 0 ]; then
    echo "  FAIL: ffmpeg was orphaned"
    pkill -f "[s]cale=480:480" 2>/dev/null
    fail=1
else
    echo "  OK: no orphan"
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: frame_stream"
    exit 0
fi
exit 1
