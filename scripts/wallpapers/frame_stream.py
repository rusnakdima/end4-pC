#!/usr/bin/env python3
"""Turn one video into a stream of small JPEG frames.

The wallpaper picker's hover preview uses this to show the clip that is under
the pointer. ffmpeg decodes the file once and writes MJPEG frames to stdout;
each frame is re-emitted as one base64 line, which QML's ``SplitParser`` can
consume without a binary-aware parser.

Usage:
    frame_stream.py <video-or-proxy-file>

The process exits when its stdout is closed (Quickshell killed the parent) and
takes ffmpeg down with it.
"""

from __future__ import annotations

import base64
import os
import shutil
import signal
import subprocess
import sys
import time

MAX_EDGE = 480
# Matches the wallpaper player's own rate, so the cell does not look slower
# than the desktop.
FPS = 30
QUALITY = 6
# Two threads: the wallpaper player is decoding the same clip at the same
# time, and a single-threaded scale+encode could not keep up with it.
THREADS = 2

# Set by the termination handler. Without it a SIGTERM that lands during the
# hardware-decoding retry would be swallowed: the handler kills ffmpeg, the
# loop sees an instant death, restarts the decoder and never exits — the
# picker would then be unable to stop the stream at all.
_STOP = False


def _cached_proxy(src: str) -> str | None:
    """The proxy __video_wallpaper.sh would hand the wallpaper player, when it
    already exists.

    Asking the shell script keeps a single definition of the cache key. This
    only ever reports a path — it never builds anything, so hovering a clip
    can never start an encode.
    """
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "__video_wallpaper.sh")
    if not os.path.isfile(script):
        return None
    try:
        out = subprocess.run(
            ["bash", script, "--proxy-path", src],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except Exception:
        return None
    path = (out.stdout or "").strip()
    if path and os.path.isfile(path) and os.path.getsize(path) > 0:
        return path
    return None


def _build_cmd(ffmpeg: str, src: str, hwaccel: bool) -> list[str]:
    cmd = [
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-loglevel", "error",
        "-re",
        "-stream_loop", "-1",
    ]
    if hwaccel:
        # Decode on the GPU. The wallpaper player is decoding the same clip at
        # the same time, and two software decodes of a 4K source is what made
        # the cell preview stutter.
        cmd += ["-hwaccel", "vaapi"]
    cmd += [
        "-i", src,
        "-an",
        "-vf", f"scale={MAX_EDGE}:{MAX_EDGE}:force_original_aspect_ratio=decrease",
        "-r", str(FPS),
        "-threads", str(THREADS),
        "-q:v", str(QUALITY),
        "-f", "mjpeg",
        "-",
    ]
    return cmd


def _terminate(proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is not None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=2)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def _next_jpeg(buf: bytes) -> tuple[bytes | None, int]:
    """Return (complete JPEG, bytes consumed), or (None, bytes to drop)."""
    pos = 2  # just past SOI
    while True:
        marker_at = buf.find(b"\xff", pos)
        if marker_at < 0 or marker_at + 1 >= len(buf):
            return None, 0

        marker = buf[marker_at + 1]
        if marker == 0xFF:  # fill byte
            pos = marker_at + 1
            continue
        if marker == 0xD9:  # EOI
            return buf[:marker_at + 2], marker_at + 2
        if marker == 0xD8:  # next image started before this one ended
            return None, marker_at
        if 0xD0 <= marker <= 0xD7:  # RSTn, no payload
            pos = marker_at + 2
            continue

        if marker_at + 4 > len(buf):
            return None, 0
        segment = (buf[marker_at + 2] << 8) | buf[marker_at + 3]
        if segment < 2:
            return None, marker_at

        if marker != 0xDA:  # not SOS: skip the whole length-prefixed segment
            pos = marker_at + 2 + segment
            continue

        # Start of scan: skip the SOS header, then look for EOI in the entropy
        # data. 0xFF 0x00 is a stuffed data byte and RST markers are allowed.
        scan = marker_at + 2 + segment
        while True:
            end_at = buf.find(b"\xff", scan)
            if end_at < 0 or end_at + 1 >= len(buf):
                return None, 0
            end_marker = buf[end_at + 1]
            if end_marker == 0x00 or 0xD0 <= end_marker <= 0xD7:
                scan = end_at + 2
                continue
            if end_marker == 0xD9:
                return buf[:end_at + 2], end_at + 2
            if end_marker == 0xD8:
                return None, end_at
            return None, end_at


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1]:
        print("usage: frame_stream.py <video-file>", file=sys.stderr)
        return 2

    src = os.path.expanduser(argv[1])
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        print("ffmpeg not found", file=sys.stderr)
        return 2
    if not os.path.isfile(src):
        print(f"no such file: {src}", file=sys.stderr)
        return 2

    # Decode the small proxy when it already exists. It is what the wallpaper
    # player uses, it carries a third of the pixels of a 4K original, and it
    # stops the cell from competing with the wallpaper for the decoder.
    proxy = _cached_proxy(src)
    if proxy:
        src = proxy

    hwaccel = True
    cmd = _build_cmd(ffmpeg, src, hwaccel)

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
    )
    if proc.stdout is None:
        _terminate(proc)
        return 1

    def stop(_signum=None, _frame=None) -> None:
        global _STOP
        _STOP = True
        _terminate(proc)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    out = sys.stdout.buffer
    buf = b""
    retried = False
    started = time.monotonic()
    try:
        while True:
            # read1, not read: read() on a buffered pipe blocks until the full
            # 64 KB arrive, so frames came out in bursts of two or three —
            # measured gaps of 253 ms and 22 stalls over 100 ms in six seconds,
            # which is the freezing seen in the cell. read1 returns as soon as
            # any bytes are available.
            chunk = proc.stdout.read1(65536)
            if not chunk:
                # A decoder that dies before producing a single frame never
                # worked: if that was VAAPI, retry once in software instead of
                # leaving the cell without a preview.
                if hwaccel and not retried and not _STOP and (time.monotonic() - started) < 5:
                    _terminate(proc)
                    retried = True
                    hwaccel = False
                    proc = subprocess.Popen(
                        _build_cmd(ffmpeg, src, False),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        stdin=subprocess.DEVNULL,
                    )
                    if proc.stdout is None:
                        _terminate(proc)
                        return 1
                    started = time.monotonic()
                    continue
                break
            buf += chunk

            while True:
                start = buf.find(b"\xff\xd8")
                if start < 0:
                    # Keep a trailing 0xFF: it may be the first half of SOI.
                    buf = buf[-1:] if buf.endswith(b"\xff") else b""
                    break
                if start > 0:
                    buf = buf[start:]

                frame, consumed = _next_jpeg(buf)
                if frame is None:
                    if consumed > 0:
                        buf = buf[consumed:]
                        continue
                    break

                buf = buf[consumed:]
                try:
                    out.write(base64.b64encode(frame) + b"\n")
                    out.flush()
                except (BrokenPipeError, OSError):
                    return 0
    finally:
        stop()
        try:
            proc.wait(timeout=2)
        except Exception:
            proc.kill()

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
