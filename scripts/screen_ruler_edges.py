#!/usr/bin/env python3
"""Edge-detection helper for the Screen Ruler (Measure Tool) overlay.

Takes one screen snapshot at startup, then answers measurement queries read
from stdin. Each query is a line: ``<mode> <x> <y>`` where mode is ``h``,
``v`` or ``b`` (both) and x/y are logical (scaled) screen coordinates.

Each answer is one JSON line on stdout, for example::

    {"mode": "h", "left": 120, "right": 340, "width": 220}

The helper converts logical coordinates to physical image pixels using the
device pixel ratio reported by Quickshell, then converts results back so QML
can draw them in its own coordinate space.
"""

from __future__ import annotations

import argparse
import io
import json
import subprocess
import sys
from typing import Optional

import numpy as np
from PIL import Image

MAX_SCAN = 640  # physical pixels searched in each direction
DEFAULT_TOLERANCE = 30


def difference(a: np.ndarray, b: np.ndarray, per_channel: bool) -> float:
    """Colour difference between two neighbouring pixels."""
    diff = np.abs(a.astype(np.int16) - b.astype(np.int16))
    if per_channel:
        return float(np.max(diff))
    return float(np.sum(diff))


def _scan_horizontal(
    image: np.ndarray,
    row: int,
    start: int,
    step: int,
    tolerance: int,
    per_channel: bool,
) -> Optional[int]:
    height, width = image.shape[:2]
    for distance in range(1, MAX_SCAN + 1):
        previous = start + step * (distance - 1)
        current = start + step * distance
        if current < 0 or current >= width:
            return None
        if difference(image[row, previous], image[row, current], per_channel) > tolerance:
            return current
    return None


def _scan_vertical(
    image: np.ndarray,
    column: int,
    start: int,
    step: int,
    tolerance: int,
    per_channel: bool,
) -> Optional[int]:
    height = image.shape[0]
    for distance in range(1, MAX_SCAN + 1):
        previous = start + step * (distance - 1)
        current = start + step * distance
        if current < 0 or current >= height:
            return None
        if difference(image[previous, column], image[current, column], per_channel) > tolerance:
            return current
    return None


def measure(
    image: np.ndarray,
    mode: str,
    x: float,
    y: float,
    ratio: float = 1.0,
    tolerance: int = DEFAULT_TOLERANCE,
    per_channel: bool = False,
) -> dict:
    """Measure edges around a logical point and return logical coordinates."""
    height, width = image.shape[:2]
    px = max(0, min(width - 1, int(round(x * ratio))))
    py = max(0, min(height - 1, int(round(y * ratio))))

    result: dict = {"mode": mode, "x": x, "y": y}

    if mode in ("h", "both"):
        left = _scan_horizontal(image, py, px, -1, tolerance, per_channel)
        right = _scan_horizontal(image, py, px, 1, tolerance, per_channel)
        left = 0 if left is None else left
        right = width - 1 if right is None else right
        result["left"] = left / ratio
        result["right"] = right / ratio
        result["width"] = max(0, (right - left) / ratio)

    if mode in ("v", "both"):
        top = _scan_vertical(image, px, py, -1, tolerance, per_channel)
        bottom = _scan_vertical(image, px, py, 1, tolerance, per_channel)
        top = 0 if top is None else top
        bottom = height - 1 if bottom is None else bottom
        result["top"] = top / ratio
        result["bottom"] = bottom / ratio
        result["height"] = max(0, (bottom - top) / ratio)

    return result


def load_image(args: argparse.Namespace) -> Image.Image:
    if args.file:
        return Image.open(args.file).convert("RGB")
    command = ["grim"]
    if args.output:
        command += ["-o", args.output]
    command += ["-"]
    raw = subprocess.run(command, check=True, stdout=subprocess.PIPE).stdout
    return Image.open(io.BytesIO(raw)).convert("RGB")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", help="wlroots output name to capture (grim -o)")
    parser.add_argument("--file", help="read a PNG instead of capturing (used by tests)")
    parser.add_argument("--ratio", type=float, default=1.0, help="device pixel ratio")
    parser.add_argument("--tolerance", type=int, default=DEFAULT_TOLERANCE)
    parser.add_argument("--per-channel", action="store_true")
    args = parser.parse_args()

    try:
        image = np.asarray(load_image(args))
    except Exception as error:  # noqa: BLE001 - report to QML, don't crash the shell
        print(json.dumps({"error": str(error)}), flush=True)
        return 1

    for line in sys.stdin:
        parts = line.split()
        if len(parts) < 3:
            continue
        mode = parts[0][:1]
        if mode not in ("h", "v", "b"):
            continue
        mode = "both" if mode == "b" else mode
        try:
            answer = measure(
                image, mode, float(parts[1]), float(parts[2]), args.ratio,
                args.tolerance, args.per_channel,
            )
        except Exception as error:  # noqa: BLE001
            answer = {"error": str(error)}
        print(json.dumps(answer), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
