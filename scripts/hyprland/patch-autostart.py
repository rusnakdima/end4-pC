#!/usr/bin/env python3
"""Rewrite the Hyprland autostart line to start Quickshell immediately.

The installer used to wrap the shell start in a BlueZ wait script. Bluetooth
status now has a CLI fallback, so the wait only delays the desktop. This
script unwraps that line and upgrades the legacy sleep/pgrep form to the same
direct `qs -n -p` invocation. It is idempotent.
"""

import argparse
import re
from pathlib import Path

LEGACY = re.compile(
    r"""hl\.exec_cmd\("sh -c 'sleep 5; pgrep -x qs >/dev/null \|\| exec qs -p ([^']+)'"\)"""
)
WRAPPED = re.compile(
    r"""hl\.exec_cmd\("bash -c '\\?"?\$HOME/\.config/quickshell/end4-pC/scripts/bluetooth/wait-for-bluez\.sh\\?" && exec qs -n -p ([^']+)'"\)"""
)
DIRECT = r'hl.exec_cmd("qs -n -p \1")'


def patch(text: str) -> tuple[str, int]:
    """Return (new text, number of autostart lines rewritten)."""
    text, legacy_count = LEGACY.subn(DIRECT, text)
    text, wrapped_count = WRAPPED.subn(DIRECT, text)
    return text, legacy_count + wrapped_count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", required=True, type=Path, help="hyprland.lua to patch")
    args = parser.parse_args()

    original = args.file.read_text()
    patched, count = patch(original)
    if count:
        args.file.write_text(patched)
        print(f"[install] autostart: started Quickshell without waiting for BlueZ ({count} line(s))")
    else:
        print("[install] autostart: already starts Quickshell directly")


if __name__ == "__main__":
    main()
