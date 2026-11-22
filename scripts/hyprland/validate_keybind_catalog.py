#!/usr/bin/env python3
"""Validate the frozen Hyprland keybind catalog.

Usage:
  python3 scripts/hyprland/validate_keybind_catalog.py [--catalog FILE]

Checks performed (all must pass for exit 0):
  1.  ids are present, unique and byte-stable (sha256 of the ordered id list).
  2.  every dispatch has a known kind.
  3.  every combo is parseable: known modifiers plus exactly one key token,
      no loop-local / concatenation leftovers.
  4.  every bind carries a non-empty human-readable ``label``.
  5.  every non-``raw`` bind's ``code`` is reproducible from its normalized
      dispatch + combo + options + description (i.e. it equals exactly what
      ``generate_keybinds.render_bind`` emits).  ``raw`` binds keep their
      original closed-form statement and are checked only for shape.
  6.  the generator's Lua output parses under ``luac -p``.
  7.  catalog <-> generated bind count parity: 207 catalog binds produce 207
      ``hl.bind`` statements; 2 of them are runtime-only (tap-super launcher)
      and therefore 205 show up in ``hyprctl binds``.
  8.  duplicate combos are limited to the intentional-duplicate whitelist.

The validator never writes to the repository: generated Lua goes to a
temporary directory that is removed on exit.  It never touches live config,
does not run ``sync.sh`` and does not call ``hyprctl reload``.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
DEFAULT_CATALOG = os.path.join(REPO, 'defaults', 'hyprland', 'keybinds.json')
GENERATOR = os.path.join(HERE, 'generate_keybinds.py')

# --- frozen expectations ----------------------------------------------------
EXPECTED_CATALOG_BINDS = 207
EXPECTED_HYPRCTL_BINDS = 205
# Tap-super launcher binds are runtime-only: they open the launcher on a Super
# tap and are excluded from the exported / hyprctl-visible bind list.
RUNTIME_ONLY_IDS = frozenset({'bind', 'bind-2'})
EXPECTED_ID_SHA256 = 'c242df6fcb7302451aea533271ada4fa67ca6ac4698abc23b40311b7db3d8cc9'

VALID_DISPATCH_KINDS = frozenset({
    'raw', 'command', 'unknown',
    'global', 'focus', 'layout',
    'window.move', 'window.drag', 'window.resize', 'window.fullscreen',
    'window.fullscreen_state', 'window.close', 'window.float', 'window.pin',
    'workspace.toggle_special',
})

MODIFIERS = frozenset({'SUPER', 'SHIFT', 'CTRL', 'ALT', 'META'})
KEY_RE = re.compile(r'^[A-Za-z0-9_:.\-]+$')
BIND_RE = re.compile(r'^\s*hl\.bind\(')

# Combos intentionally shared by two binds (different dispatchers/options).
DUPLICATE_COMBO_WHITELIST = {
    'SUPER + SHIFT + S': {'utilities', 'utilities-2'},
    'SUPER + SHIFT + A': {'utilities-3', 'utilities-4'},
    'CTRL + Print': {'utilities-8', 'utilities-9'},
}


def load_catalog(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def fail(errors, msg):
    errors.append(msg)


# --- individual checks ------------------------------------------------------
def check_ids(binds, errors):
    ids = [b.get('id') for b in binds]
    if any(not isinstance(i, str) or not i for i in ids):
        fail(errors, 'ids: every bind needs a non-empty string id')
        return
    dupes = sorted(i for i, n in Counter(ids).items() if n > 1)
    if dupes:
        fail(errors, f'ids: duplicates found: {dupes}')
    digest = hashlib.sha256('\n'.join(ids).encode('utf-8')).hexdigest()
    if digest != EXPECTED_ID_SHA256:
        fail(errors, f'ids: byte-stability digest changed: {digest} '
                     f'(expected {EXPECTED_ID_SHA256})')


def check_dispatch(binds, errors):
    for b in binds:
        kind = (b.get('dispatch') or {}).get('kind')
        if kind not in VALID_DISPATCH_KINDS:
            fail(errors, f"{b.get('id')}: unknown dispatch kind {kind!r}")


def check_combos(binds, errors):
    for b in binds:
        combo = b.get('combo')
        bid = b.get('id')
        if not isinstance(combo, str) or not combo.strip():
            fail(errors, f'{bid}: empty combo')
            continue
        parts = [p.strip() for p in combo.split('+')]
        if any(not p for p in parts):
            fail(errors, f'{bid}: empty combo token in {combo!r}')
            continue
        for part in parts:
            if not KEY_RE.fullmatch(part):
                fail(errors, f'{bid}: unparseable combo token {part!r} in {combo!r}')
        keys = [p for p in parts if p.upper() not in MODIFIERS]
        if len(keys) != 1:
            fail(errors, f'{bid}: combo {combo!r} has {len(keys)} key tokens (expected 1)')
        # Loop-local leftovers such as `key[1]` or `"CTRL + " .. key[1]` must
        # never survive into a frozen catalog combo.
        if '[' in combo or ']' in combo or '..' in combo:
            fail(errors, f'{bid}: combo {combo!r} contains loop-local/concat artifacts')


def check_labels(binds, errors):
    for b in binds:
        label = b.get('label')
        if not isinstance(label, str) or not label.strip():
            fail(errors, f"{b.get('id')}: missing/empty label")


def check_code(binds, errors):
    """Non-raw code must be exactly reproducible from the dispatch fields."""
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import generate_keybinds as gen  # noqa: WPS433 (local by design)

    for b in binds:
        bid = b.get('id')
        kind = (b.get('dispatch') or {}).get('kind')
        code = b.get('code')
        if not isinstance(code, str) or not code:
            fail(errors, f'{bid}: missing code')
            continue
        if kind == 'raw':
            # Raw binds keep the original closed-form statement verbatim.
            if 'hl.bind(' not in code or 'key[' in code:
                fail(errors, f'{bid}: raw code is not a closed form: {code[:80]!r}')
            continue
        expected = gen.render_bind(b, {}, 'bridge')
        if code != expected:
            fail(errors, f'{bid}: non-raw code is not reproducible from dispatch\n'
                         f'    have: {code}\n'
                         f'    want: {expected}')
        if '\n' in code or not code.startswith('hl.bind('):
            fail(errors, f'{bid}: non-raw code is not a standalone statement')


def check_generated(catalog_path, binds, errors):
    """Generate Lua to a temp dir, lint it, and check bind-count parity."""
    luac = shutil.which('luac')
    if luac is None:
        fail(errors, 'luac not found on PATH')
        return
    tmp = tempfile.mkdtemp(prefix='keybind-catalog-')
    try:
        main = os.path.join(tmp, 'main.lua')
        custom = os.path.join(tmp, 'custom.lua')
        proc = subprocess.run(
            [sys.executable, GENERATOR, '--catalog', catalog_path,
             '--main-out', main, '--custom-out', custom],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            fail(errors, f'generator failed ({proc.returncode}): {proc.stderr.strip()}')
            return
        lint = subprocess.run([luac, '-p', main, custom],
                              capture_output=True, text=True)
        if lint.returncode != 0:
            fail(errors, f'luac -p failed ({lint.returncode}): {lint.stderr.strip()}')

        generated = 0
        for path in (main, custom):
            with open(path, encoding='utf-8') as fh:
                generated += sum(1 for line in fh if BIND_RE.match(line))
        if generated != len(binds):
            fail(errors, f'count parity: catalog has {len(binds)} binds but '
                         f'generated Lua has {generated}')
        if len(binds) != EXPECTED_CATALOG_BINDS:
            fail(errors, f'catalog bind count {len(binds)} != expected '
                         f'{EXPECTED_CATALOG_BINDS}')
        expected_hyprctl = len(binds) - len(RUNTIME_ONLY_IDS)
        if expected_hyprctl != EXPECTED_HYPRCTL_BINDS:
            fail(errors, f'hyprctl parity: {len(binds)} - {len(RUNTIME_ONLY_IDS)} '
                         f'= {expected_hyprctl} != expected {EXPECTED_HYPRCTL_BINDS}')
        present = {b.get('id') for b in binds}
        missing = RUNTIME_ONLY_IDS - present
        if missing:
            fail(errors, f'runtime-only ids missing from catalog: {sorted(missing)}')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def check_duplicates(binds, errors):
    by_combo = defaultdict(set)
    for b in binds:
        by_combo[b.get('combo')].add(b.get('id'))
    for combo, ids in by_combo.items():
        if len(ids) < 2:
            continue
        allowed = DUPLICATE_COMBO_WHITELIST.get(combo)
        if allowed is None:
            fail(errors, f'duplicate combo not in whitelist: {combo!r} -> {sorted(ids)}')
        elif ids != allowed:
            fail(errors, f'duplicate combo {combo!r} ids {sorted(ids)} != '
                         f'whitelist {sorted(allowed)}')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--catalog', default=DEFAULT_CATALOG,
                    help='catalog JSON (default: repo defaults/hyprland/keybinds.json)')
    args = ap.parse_args()

    errors = []
    catalog = load_catalog(args.catalog)
    binds = catalog.get('binds')
    if not isinstance(binds, list):
        print('FAIL: catalog has no "binds" list', file=sys.stderr)
        return 1

    check_ids(binds, errors)
    check_dispatch(binds, errors)
    check_combos(binds, errors)
    check_labels(binds, errors)
    check_code(binds, errors)
    check_generated(args.catalog, binds, errors)
    check_duplicates(binds, errors)

    if errors:
        print(f'FAIL: {len(errors)} catalog validation error(s):', file=sys.stderr)
        for err in errors:
            print(f'  - {err}', file=sys.stderr)
        return 1

    counts = Counter(b.get('dispatch', {}).get('kind') for b in binds)
    print(f'OK: {len(binds)} binds '
          f'({counts["raw"]} raw, {len(binds) - counts["raw"]} normalized), '
          f'{EXPECTED_HYPRCTL_BINDS} hyprctl-visible; '
          f'ids unique + byte-stable; combos/dispatch/labels/code valid; '
          f'generated Lua passes luac -p; duplicates whitelisted.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
