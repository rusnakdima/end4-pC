#!/usr/bin/env python3
"""Verify that every Material Symbols name used by the shell exists in the
Google Material Symbols Rounded pack.

The pack is pinned in tests/material-symbols-rounded.txt, generated from
google/material-design-icons/variablefont/MaterialSymbolsRounded[...].codepoints.

Fluent icons (modules/waffle) use their own SVG set and are not part of the
Material font, so that tree is skipped here.
"""
import difflib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = os.path.join(ROOT, "tests", "material-symbols-rounded.txt")

ICON_COMPONENTS = (
    "MaterialSymbol",
    "OptionalMaterialSymbol",
    "MaterialShapeWrappedMaterialSymbol",
    "MaterialSymbolWrappedMaterialShape",
)
ICON_KEYS = (
    "icon",
    "buttonIcon",
    "iconText",
    "iconName",
    "materialSymbol",
    "hintIcon",
    "confirmButtonIcon",
    "buttonIconName",
    "hintSymbol",
)
RETURN_FILES = (
    "modules/common/Icons.qml",
    "modules/common/functions/NotificationUtils.qml",
    "services/Audio.qml",
    "services/AudioDevices.qml",
)
SNAKE_RE = re.compile(r"^[a-z0-9][a-z0-9_]*$")
SKIP_DIRS = (".git", "tests/shell-tests/translations", "modules/waffle")

valid = set()
with open(NAMES, encoding="utf-8") as f:
    for line in f:
        name = line.strip()
        if name:
            valid.add(name)


def is_comparison_operand(prefix, suffix):
    """A string compared with ==/!= is a value, not an icon name."""
    before = prefix.rstrip()
    after = suffix.lstrip()
    return before.endswith(("==", "!=", "===", "!==")) or after.startswith(("==", "!=", "===", "!=="))


def expression_strings(line, start):
    """Quoted strings in one property expression, stopping at a depth-0 comma."""
    out = []
    depth = 0
    i = start
    in_str = None
    esc = False
    buf = []
    quote_start = 0
    while i < len(line):
        ch = line[i]
        if in_str:
            if esc:
                buf.append(ch)
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == in_str:
                value = "".join(buf)
                suffix = line[i + 1:]
                out.append((value, line[start:quote_start], suffix))
                buf = []
                in_str = None
            else:
                buf.append(ch)
        else:
            if ch in "\"'":
                in_str = ch
                quote_start = i
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif ch == "," and depth == 0:
                break
            elif ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
        i += 1
    return out


def add(found, line, start, path, lineno, context):
    for value, prefix, suffix in expression_strings(line, start):
        if not SNAKE_RE.match(value) or value.isdigit():
            continue
        if is_comparison_operand(prefix, suffix):
            continue
        found.append((value, path, lineno, context, line.strip()))


found = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    rel_dir = os.path.relpath(dirpath, ROOT)
    if any(part in rel_dir.split(os.sep) for part in (".git",)):
        continue
    if rel_dir.startswith("tests"):
        continue
    if rel_dir == "modules/waffle" or rel_dir.startswith("modules/waffle" + os.sep):
        continue
    for fn in filenames:
        if not (fn.endswith(".qml") or fn.endswith(".js")):
            continue
        path = os.path.join(dirpath, fn)
        rel = os.path.relpath(path, ROOT)
        try:
            lines = open(path, encoding="utf-8").read().splitlines()
        except Exception:
            continue

        depth = 0
        material_depth = None
        for lineno, line in enumerate(lines, 1):
            opened = None
            if material_depth is None:
                for t in ICON_COMPONENTS:
                    m = re.search(r"\b" + t + r"\s*\{", line)
                    if m:
                        opened = m.end()
                        material_depth = depth + 1
                        break

            if opened is not None:
                m = re.search(r"\btext\s*:", line[opened:])
                if m:
                    add(found, line, opened + m.end(), rel, lineno, "material-text")
            elif material_depth is not None and depth == material_depth:
                m = re.search(r"\btext\s*:", line)
                if m:
                    add(found, line, m.end(), rel, lineno, "material-text")

            for key in ICON_KEYS:
                m = re.search(r"\b" + key + r"\s*:", line)
                if m:
                    add(found, line, m.end(), rel, lineno, key)
                    break

            depth += line.count("{") - line.count("}")
            if material_depth is not None and depth < material_depth:
                material_depth = None

for rel in RETURN_FILES:
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        continue
    for lineno, line in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
        m = re.search(r"\breturn\b", line)
        if not m:
            continue
        expr = line[m.end():].lstrip()
        if not (expr.startswith('"') or "?" in expr):
            continue
        add(found, line, m.end(), rel, lineno, "return")


def bundled_font_ligatures():
    """Ligature names in the font the shell actually renders with.

    Google's pack is the reference, but the shipped font can lag a few
    icons behind; a name that exists only in Google still renders as text.
    Returns None when fontTools is unavailable, so the check is skipped
    rather than failing the build on a machine without it.
    """
    font_path = os.path.join(ROOT, "assets", "fonts", "MaterialSymbolsRounded.ttf")
    if not os.path.exists(font_path):
        return None
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        return None

    font = TTFont(font_path)
    cmap = font.getBestCmap()
    reverse = {}
    for codepoint, glyph in cmap.items():
        reverse.setdefault(glyph, chr(codepoint))

    names = set()
    for lookup in font["GSUB"].table.LookupList.Lookup:
        for sub in lookup.SubTable:
            if lookup.LookupType == 7 and hasattr(sub, "ExtSubTable"):
                ligatures = getattr(sub.ExtSubTable, "ligatures", None)
            else:
                ligatures = getattr(sub, "ligatures", None)
            if not ligatures:
                continue
            for first, entries in ligatures.items():
                for entry in entries:
                    chars = [reverse.get(g) for g in [first] + list(entry.Component)]
                    if all(chars):
                        names.add("".join(chars).lower())
    return names


seen = set()
missing = []
for name, path, lineno, context, line in found:
    if name in valid:
        continue
    ident = (name, path, lineno)
    if ident in seen:
        continue
    seen.add(ident)
    missing.append((name, path, lineno, context, line))

if missing:
    print(f"FAIL: {len(missing)} Material icon name(s) missing from the Google pack:", file=sys.stderr)
    for name, path, lineno, context, line in sorted(missing):
        close = difflib.get_close_matches(name, valid, n=3, cutoff=0.5)
        suggestion = ", ".join(close) if close else "no close match"
        print(f"  {path}:{lineno} [{context}] {name!r} -> {suggestion}", file=sys.stderr)
        print(f"    {line}", file=sys.stderr)
    sys.exit(1)

# The shipped font is what Qt renders with, so it must cover the names too.
font_names = bundled_font_ligatures()
if font_names is None:
    print("NOTE: fontTools unavailable, skipped the bundled font check")
else:
    missing_from_font = sorted(set(f[0] for f in found) - font_names)
    if missing_from_font:
        print(f"FAIL: {len(missing_from_font)} name(s) are in Google's pack but not in the "
              f"shipped font, so they render as text:", file=sys.stderr)
        for name in missing_from_font:
            close = difflib.get_close_matches(name, font_names, n=3, cutoff=0.5)
            print(f"  {name!r} -> {', '.join(close) or 'no close match in the font'}", file=sys.stderr)
        sys.exit(1)

print(f"PASS: {len(set(f[0] for f in found))} Material icon names are in the Google pack "
      f"and in the shipped font")
