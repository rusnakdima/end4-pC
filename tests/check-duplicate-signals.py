#!/usr/bin/env python3
"""Find QML files that declare a change signal for a property that exists.

The QML engine rejects a type that declares both a property ``foo`` and a
signal ``fooChanged``: the property generates that signal itself, so the
second declaration is a duplicate. The engine reports it as

    Duplicate signal name: invalid override of property change signal
    or superclass signal

and the file then fails to compile, which takes down every type that imports
it. qmllint does not report this for singleton files, so the check is done
here instead.

Properties and signals are matched per scope, so an inline component
(``component Foo: Item { ... }``) is compared against itself and not against
the type that contains it.

Usage: check-duplicate-signals.py <file-or-directory> [...]
"""

import re
import sys
from pathlib import Path

# The type of a property, after the "property" keyword. The name of the
# property is the last identifier before the colon or the assignment.
PROPERTY = re.compile(
    r"\s*(?:readonly\s+|required\s+|default\s+)*"
    r"(?:[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)(?:<[^>]*>)?\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
)
# A signal declaration: signal <name>(...)
SIGNAL_DECL = re.compile(r"\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def scopes(text: str):
    """Yield (scope_id, kind, name) for every property and signal."""
    # Brace depth is enough to tell scopes apart, but a scope is identified
    # by the position it started at, so two different scopes at the same
    # depth stay separate.
    stack = [0]
    positions = {0: 0}
    scopes_found = {}
    index = 0
    length = len(text)

    # Strip comments and strings so braces inside them do not confuse the
    # depth tracking. The replacement keeps the length, so offsets still
    # point at the original text.
    cleaned = []
    i = 0
    while i < length:
        ch = text[i]
        if ch == "/" and i + 1 < length and text[i + 1] == "/":
            end = text.find("\n", i)
            if end == -1:
                end = length
            cleaned.append(" " * (end - i))
            i = end
            continue
        if ch == "/" and i + 1 < length and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            end = length if end == -1 else end + 2
            cleaned.append(" " * (end - i))
            i = end
            continue
        if ch in "\"'":
            quote = ch
            start = i
            i += 1
            while i < length and text[i] != quote:
                if text[i] == "\\":
                    i += 1
                i += 1
            i = min(i + 1, length)
            cleaned.append(" " * (i - start))
            continue
        cleaned.append(ch)
        i += 1
    text = "".join(cleaned)

    for match in re.finditer(r"[{}]|\b(?:property|signal)\b", text):
        token = match.group(0)
        if token == "{":
            stack.append(len(positions))
            positions[len(positions)] = match.start()
        elif token == "}":
            if len(stack) > 1:
                stack.pop()
        else:
            scope = stack[-1]
            rest = text[match.end():]
            if token == "property":
                prop = PROPERTY.match(text, match.end())
                if prop:
                    scopes_found.setdefault(scope, {"properties": set(), "signals": {}})
                    scopes_found[scope]["properties"].add(prop.group(1))
            else:
                sig = SIGNAL_DECL.match(text, match.end())
                if sig:
                    name = sig.group(1)
                    scopes_found.setdefault(scope, {"properties": set(), "signals": {}})
                    scopes_found[scope]["signals"][name] = match.start()
    return scopes_found


def check(path: Path) -> list:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    problems = []
    for scope, data in scopes_found_for(text).items():
        for name, offset in data["signals"].items():
            if name.endswith("Changed") and name[: -len("Changed")] in data["properties"]:
                line = text.count("\n", 0, offset) + 1
                problems.append((line, name[: -len("Changed")]))
    return problems


def scopes_found_for(text: str):
    return scopes(text)


def main(argv) -> int:
    if len(argv) < 2:
        print("usage: check-duplicate-signals.py <file-or-directory> [...]")
        return 2

    files = []
    for arg in argv[1:]:
        path = Path(arg)
        if path.is_dir():
            files.extend(sorted(path.rglob("*.qml")))
        elif path.suffix == ".qml":
            files.append(path)

    status = 0
    for file in files:
        for line, prop in check(file):
            status = 1
            print(f"{file}:{line}: signal {prop}Changed() duplicates the "
                  f"change signal of property {prop}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
