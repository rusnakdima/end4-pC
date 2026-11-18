#!/usr/bin/env python3
"""Find config-bound controls that lost their live link to the config.

A control such as ConfigSwitch writes its own ``checked`` property when the
user clicks it. That imperative assignment destroys the declarative
``checked: Config.options.someKey`` binding, so the control stops reflecting
changes made in another surface. The fix is a ``ConfigBinding`` element next
to the control (see modules/common/widgets/ConfigBinding.qml).

This check runs over the parameters listed in tests/config-sync-params.txt,
because only parameters that exist in more than one surface need the extra
element. For every block of an editable type whose ``checked`` / ``value`` is
bound to one of those parameters, the block must also declare a
``ConfigBinding``.

``ConfigComboBox`` is intentionally not checked: its ``currentValue`` is
never self-assigned, and the widget keeps its inner ``currentIndex`` in sync
by itself.

Usage: check-config-sync.py [file-or-directory ...]
       defaults to modules, services and welcome.qml
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

EDITABLE_TYPES = {
    "ConfigSwitch",
    "ConfigSpinBox",
    "ConfigSlider",
    "ConfigTextArea",
}

BLOCK_HEADER = re.compile(r"^\s*([A-Z][\w.]*)\s*$")
BINDING = re.compile(r"\b(checked|value)\s*:\s*Config\.options\.([\w.]+)")


def read_allowlist(path: Path) -> list[str]:
    if not path.exists():
        return []
    entries: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        entries.append(line)
    return entries


def block_spans(text: str):
    """Yield (header_type, start_line, end_line, body) for every QML block.

    Braces inside strings and comments are skipped; a header is only treated
    as a type when the whole text before the opening brace is an identifier
    (so ``onValueChanged: {`` becomes an anonymous block).
    """
    stack: list[dict] = []
    line = 1
    i = 0
    n = len(text)
    in_line_comment = False
    in_block_comment = False
    quote = ""

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if ch == "\n":
            line += 1
            in_line_comment = False
            i += 1
            continue

        if in_line_comment:
            i += 1
            continue
        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = ""
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if ch in ("'", '"', "`"):
            quote = ch
            i += 1
            continue

        if ch == "{":
            line_start = text.rfind("\n", 0, i) + 1
            header = text[line_start:i]
            m = BLOCK_HEADER.match(header)
            stack.append({
                "type": m.group(1) if m else None,
                "line": line,
                "body_start": i + 1,
            })
        elif ch == "}" and stack:
            block = stack.pop()
            block["body"] = text[block["body_start"]:i]
            block["end_line"] = line
            yield block
        i += 1


def check_file(path: Path, allowed: set[str], root: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="ignore")
    problems: list[str] = []
    try:
        display = path.relative_to(root)
    except ValueError:
        display = path
    for block in block_spans(text):
        if block["type"] not in EDITABLE_TYPES:
            continue
        body = block["body"]
        matches = [m for m in BINDING.finditer(body) if m.group(2) in allowed]
        if not matches:
            continue
        if "ConfigBinding" in body:
            continue
        seen: set[str] = set()
        for match in matches:
            key = match.group(2)
            if key in seen:
                continue
            seen.add(key)
            problems.append(
                f"{display}:{block['line']}: "
                f"{block['type']} binds {key} without a ConfigBinding"
            )
    return problems


def iter_files(targets: list[Path]):
    for target in targets:
        if target.is_dir():
            yield from sorted(target.rglob("*.qml"))
        elif target.suffix == ".qml":
            yield target


def main(argv: list[str]) -> int:
    repo = Path(__file__).resolve().parent.parent
    allowlist = read_allowlist(repo / "tests" / "config-sync-params.txt")
    if not allowlist:
        print("check-config-sync: tests/config-sync-params.txt is empty", file=sys.stderr)
        return 2
    allowed = set(allowlist)

    if len(argv) > 1:
        targets = [Path(arg).resolve() for arg in argv[1:]]
    else:
        targets = [repo / "modules", repo / "services", repo / "welcome.qml"]

    problems: list[str] = []
    for path in iter_files(targets):
        problems.extend(check_file(path, allowed, repo))
    if problems:
        for problem in problems:
            print(problem)
        print(f"\n{len(problems)} control(s) need a ConfigBinding.", file=sys.stderr)
        return 1

    print(f"check-config-sync: {len(allowed)} parameter(s), no missing ConfigBinding")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
