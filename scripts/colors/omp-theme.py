#!/usr/bin/env python3
"""Generate an oh-my-posh theme from the end4-pC Material 3 palette.

The end4-pC shell keeps the Material 3 tokens of the current wallpaper in
``~/.local/state/quickshell/user/generated/colors.json``. This script turns
those tokens into an oh-my-posh (version 4) configuration so the shell prompt
follows the wallpaper like the rest of the theme.

Usage:
    omp-theme.py [OUTPUT] [PALETTE]

    OUTPUT   path of the theme to write
             (default: /home/dmitriy/.config/oh-my-posh/themes/end4-m3.omp.json)
    PALETTE  path of the Material 3 token file
             (default: ~/.local/state/quickshell/user/generated/colors.json)

If the palette is missing or unparsable the script exits 0 without writing
anything: the previous theme stays in place instead of the prompt losing its
colours.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile

DEFAULT_OUTPUT = "/home/dmitriy/.config/oh-my-posh/themes/end4-m3.omp.json"
DEFAULT_PALETTE = os.path.expanduser(
    "~/.local/state/quickshell/user/generated/colors.json"
)

SCHEMA = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json"

# Material 3 token -> prompt role. The first entry of every role is the
# fallback when the palette does not contain that token.
ROLES = {
    "on_surface": ("on_surface", "surface", "on_surface"),
    "on_surface_variant": ("on_surface_variant", "surface", "on_surface"),
    "on_primary": ("on_primary", "primary", "on_surface"),
    "on_primary_container": ("on_primary_container", "primary_container", "on_surface"),
    "primary": ("primary", "primary", "on_surface"),
    "primary_container": ("primary_container", "primary_container", "on_surface"),
    "secondary_container": ("secondary_container", "secondary_container", "on_surface"),
    "surface": ("surface", "surface", "on_surface"),
    "surface_container": ("surface_container", "surface_container", "on_surface"),
    "surface_container_high": ("surface_container_high", "surface_container_high", "on_surface"),
    "outline": ("outline", "surface_container", "on_surface"),
    "error": ("error", "surface_container", "on_surface"),
}


def normalize(value: str) -> str:
    """Return a #rrggbb string for a Material 3 token value."""
    if not isinstance(value, str):
        return ""
    value = value.strip()
    if not value:
        return ""
    if not value.startswith("#"):
        value = "#" + value
    if len(value) == 4:  # #abc
        value = "#" + "".join(ch * 2 for ch in value[1:])
    if len(value) != 7:
        return ""
    try:
        int(value[1:], 16)
    except ValueError:
        return ""
    return value.lower()


def load_palette(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    tokens = {}
    for name, value in data.items():
        color = normalize(value)
        if color:
            tokens[name] = color
    return tokens


def color(tokens: dict, role: str) -> str:
    """Resolve a prompt role to a hex colour from the palette."""
    for name in ROLES.get(role, (role,)):
        if name in tokens:
            return tokens[name]
    return "#ffffff"


def segment(name: str, text: str, foreground: str, background: str) -> dict:
    return {
        "type": name,
        "style": "diamond",
        "foreground": foreground,
        "background": background,
        "template": text,
    }


def build_theme(tokens: dict) -> dict:
    on_surface = color(tokens, "on_surface")
    on_surface_variant = color(tokens, "on_surface_variant")
    on_primary = color(tokens, "on_primary")
    on_primary_container = color(tokens, "on_primary_container")
    primary = color(tokens, "primary")
    primary_container = color(tokens, "primary_container")
    secondary_container = color(tokens, "secondary_container")
    surface_container = color(tokens, "surface_container")
    surface_container_high = color(tokens, "surface_container_high")
    error = color(tokens, "error")

    left = [
        segment("session", "{{ .UserName }}@{{ .HostName }}", on_surface, surface_container_high),
        segment("path", "{{ .Path }}", on_primary_container, primary_container),
        segment("git", "{{ .HEAD }}{{ if .Status.Behind }} ↓{{ .Status.Behind }}{{ end }}{{ if .Status.Ahead }} ↑{{ .Status.Ahead }}{{ end }}{{ if .Status.Conflicted }} ✗{{ .Status.Conflicted }}{{ end }}", on_primary, primary),
        segment("python", "{{ .Full }}", on_surface, surface_container),
        segment("node", "{{ .Full }}", on_surface, surface_container),
        segment(
            "exit",
            "{{ if eq .Code 0 }}{{ else }}{{ .Code }}{{ end }}",
            # oh-my-posh renders segment colours through the template engine,
            # so the exit code can pick its own colour.
            "{{ if eq .Code 0 }}" + on_surface + "{{ else }}" + error + "{{ end }}",
            surface_container,
        ),
    ]

    right = [
        segment("battery", "{{ .Icon }} {{ .Percentage }}", on_primary, secondary_container),
        segment("time", "{{ .CurrentDate | date .Format }}", on_surface, surface_container_high),
    ]

    return {
        "$schema": SCHEMA,
        "version": 4,
        "final_space": True,
        "blocks": [
            {
                "type": "prompt",
                "alignment": "left",
                "segments": left,
            },
            {
                "type": "rprompt",
                "alignment": "right",
                "segments": right,
            },
        ],
    }


def write_theme(theme: dict, path: str) -> bool:
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    handle = None
    try:
        fd, tmp = tempfile.mkstemp(prefix=".omp-theme-", dir=directory or ".")
        handle = os.fdopen(fd, "w", encoding="utf-8")
        json.dump(theme, handle, indent=2)
        handle.write("\n")
        handle.close()
        handle = None
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except OSError:
        if handle is not None:
            handle.close()
        return False
    return True


def main(argv: list) -> int:
    output = argv[1] if len(argv) > 1 and argv[1] else DEFAULT_OUTPUT
    palette_path = argv[2] if len(argv) > 2 and argv[2] else DEFAULT_PALETTE

    tokens = load_palette(palette_path)
    if not tokens:
        # No usable palette: keep the previous theme.
        return 0

    if not write_theme(build_theme(tokens), output):
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
