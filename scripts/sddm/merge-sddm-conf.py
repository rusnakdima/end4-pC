#!/usr/bin/env python3
"""Idempotently set the end4-pC-managed keys in an SDDM config drop-in.

Only InputMethod, GreeterEnvironment and Current are owned by this project.
Every other line in the file (DisplayServer, MaximumUid, local overrides,
comments) is preserved verbatim. Managed lines are replaced in place rather
than appended, so repeated runs produce byte-identical output.
"""

import argparse
from pathlib import Path

MANAGED = {
    "General": {
        "InputMethod": "qtvirtualkeyboard",
        "GreeterEnvironment": (
            "QML2_IMPORT_PATH=/usr/share/sddm/themes/ii-sddm-theme/Components/"
        ),
    },
    "Theme": {
        "Current": "ii-sddm-theme",
    },
}


def merge(text: str) -> str:
    lines = text.splitlines()
    kept: list[str] = []
    section = ""
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
            kept.append(line)
            continue
        if "=" in line:
            key = line.split("=", 1)[0].strip()
            if key in MANAGED.get(section, {}):
                continue
        kept.append(line)

    for section, values in MANAGED.items():
        start = next(
            (i for i, line in enumerate(kept) if line.strip() == f"[{section}]"),
            None,
        )
        if start is None:
            if kept and kept[-1].strip():
                kept.append("")
            kept.append(f"[{section}]")
            start = len(kept) - 1
        insert_at = start + 1
        while insert_at < len(kept) and not kept[insert_at].strip().startswith("["):
            insert_at += 1
        kept[insert_at:insert_at] = [
            f"{key}={value}" for key, value in values.items()
        ]

    return "\n".join(kept).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", required=True, help="SDDM config drop-in to update")
    args = parser.parse_args()

    path = Path(args.file)
    path.parent.mkdir(parents=True, exist_ok=True)
    before = path.read_text() if path.exists() else ""
    after = merge(before)
    if after != before:
        path.write_text(after)


if __name__ == "__main__":
    main()
