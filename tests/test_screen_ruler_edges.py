"""Tests for the Screen Ruler edge-detection helper."""

import importlib.util
from pathlib import Path

import numpy as np

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "screen_ruler_edges.py"
spec = importlib.util.spec_from_file_location("screen_ruler_edges", SCRIPT)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def synthetic_image(scale: int = 1) -> np.ndarray:
    """White canvas with a black block at x=50..119, y=20..69 (logical)."""
    height, width = 100 * scale, 200 * scale
    image = np.full((height, width, 3), 255, dtype=np.uint8)
    image[20 * scale:70 * scale, 50 * scale:120 * scale] = 0
    return image


def test_horizontal_edges() -> None:
    answer = helper.measure(synthetic_image(), "h", 80, 40)
    assert 49 <= answer["left"] <= 51
    assert 119 <= answer["right"] <= 121
    assert 68 <= answer["width"] <= 72


def test_vertical_edges() -> None:
    answer = helper.measure(synthetic_image(), "v", 80, 40)
    assert 19 <= answer["top"] <= 21
    assert 69 <= answer["bottom"] <= 71
    assert 48 <= answer["height"] <= 52


def test_both_edges() -> None:
    answer = helper.measure(synthetic_image(), "both", 80, 40)
    assert answer["width"] > 0 and answer["height"] > 0


def test_scaled_screen_returns_logical_coordinates() -> None:
    answer = helper.measure(synthetic_image(2), "h", 80, 40, ratio=2)
    assert 49 <= answer["left"] <= 51
    assert 119 <= answer["right"] <= 121
    assert 68 <= answer["width"] <= 72


def test_outside_block_finds_nearest_edges() -> None:
    answer = helper.measure(synthetic_image(), "h", 30, 40)
    assert answer["right"] == 50


def test_missing_edge_falls_back_to_screen_bounds() -> None:
    image = np.full((100, 200, 3), 128, dtype=np.uint8)
    answer = helper.measure(image, "both", 100, 50)
    assert answer["left"] == 0
    assert answer["right"] == 199
    assert answer["top"] == 0
    assert answer["bottom"] == 99


def test_per_channel_tolerance_is_stricter() -> None:
    image = np.full((100, 200, 3), 255, dtype=np.uint8)
    image[:, :100] = [240, 240, 240]
    assert helper.measure(image, "h", 150, 50, tolerance=40)["left"] == 99
    assert helper.measure(image, "h", 150, 50, tolerance=40, per_channel=True)["left"] == 0
