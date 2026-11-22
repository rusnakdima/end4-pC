#!/usr/bin/env python3
"""Validate the frozen Hyprland keybind catalog (and optionally a user overlay).

Usage:
  python3 scripts/hyprland/validate_keybind_catalog.py [--catalog FILE]
      [--overlay FILE] [--bless]

Checks performed (all must pass for exit 0):
  1.  ids are present, unique and byte-stable (sha256 of the ordered id list),
      compared against a checked-in baseline (defaults/hyprland/keybinds.baseline.json).
  2.  every dispatch has a known kind.
  3.  every combo is parseable: known modifiers plus exactly one key token,
      no loop-local / concatenation leftovers.
  4.  every bind carries a non-empty human-readable ``label``.
  5.  every non-``raw`` bind's ``code`` is reproducible from its normalized
      dispatch + combo + options + description. ``raw`` binds keep their
      original closed-form statement; we check that every token of the
      resolved combo actually appears in its first-argument source, and that
      no unresolved loop local (``key[1]`` etc.) survives.
  6.  the generator's Lua output parses under ``luac -p``.
  7.  catalog <-> generated bind count parity, and runtime-only ids exist.
  8.  duplicate combos are limited to the intentional-duplicate whitelist.
  9.  the generated commands JSON is keyed by exactly the command-bind ids,
      and every generated bridge shortcut has a commands entry.
  10. when ``--overlay FILE`` is given: the overlay is schema-validated, the
      merged bind list is structurally validated, and a second generation
      run (with the overlay applied) is linted and commands-checked too.

The validator never writes to the repository except with ``--bless`` (which
only writes the baseline file). Generated Lua/JSON goes to a temporary
directory that is removed on exit. It never touches live config, does not run
sync.sh and does not call hyprctl reload.

When a deliberate catalog change is made (new bind, renamed id, new intentional
duplicate), review the diff and run ``--bless`` to refresh the baseline.
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
BASELINE_FILE = os.path.join(REPO, 'defaults', 'hyprland', 'keybinds.baseline.json')
GENERATOR = os.path.join(HERE, 'generate_keybinds.py')

# Embedded fallback baseline. The checked-in baseline file is authoritative
# when present; these values keep the validator usable without it.
FALLBACK_BASELINE = {
    'catalog_binds': 207,
    'hyprctl_binds': 205,
    'runtime_only_ids': ['bind', 'bind-2'],
    'id_sha256': 'c242df6fcb7302451aea533271ada4fa67ca6ac4698abc23b40311b7db3d8cc9',
    'duplicate_combo_whitelist': {
        'SUPER + SHIFT + S': ['utilities', 'utilities-2'],
        'SUPER + SHIFT + A': ['utilities-3', 'utilities-4'],
        'CTRL + Print': ['utilities-8', 'utilities-9'],
    },
}

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
LOOP_LOCAL_RE = re.compile(r'\b\w+\s*\[\s*i\s*\]')
BRIDGE_RE = re.compile(r'quickshell:runCommand:([^"]+)')


def load_json(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def load_baseline():
    if os.path.exists(BASELINE_FILE):
        data = load_json(BASELINE_FILE)
        # Accept a partial baseline by filling gaps from the fallback.
        merged = dict(FALLBACK_BASELINE)
        merged.update(data)
        return merged
    return dict(FALLBACK_BASELINE)


def id_digest(binds):
    ids = [b.get('id') for b in binds]
    return hashlib.sha256('\n'.join(ids).encode('utf-8')).hexdigest()


def find_duplicate_combos(binds):
    by_combo = defaultdict(set)
    for b in binds:
        by_combo[b.get('combo')].add(b.get('id'))
    return {c: sorted(ids) for c, ids in by_combo.items() if len(ids) > 1}


def bless(binds):
    base = load_baseline()
    runtime = sorted(base['runtime_only_ids'])
    data = {
        'catalog_binds': len(binds),
        'hyprctl_binds': len(binds) - len(runtime),
        'runtime_only_ids': runtime,
        'id_sha256': id_digest(binds),
        'duplicate_combo_whitelist': find_duplicate_combos(binds),
    }
    with open(BASELINE_FILE, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=1, ensure_ascii=False)
        fh.write('\n')
    print(f'blessed baseline: {BASELINE_FILE}')
    print(f'  catalog_binds={data["catalog_binds"]} '
          f'hyprctl_binds={data["hyprctl_binds"]} '
          f'id_sha256={data["id_sha256"][:12]}... '
          f'duplicates={len(data["duplicate_combo_whitelist"])}')
    return 0


def fail(errors, msg):
    errors.append(msg)


# --- individual checks -------------------------------------------------------
def check_ids(binds, baseline, errors):
    ids = [b.get('id') for b in binds]
    if any(not isinstance(i, str) or not i for i in ids):
        fail(errors, 'ids: every bind needs a non-empty string id')
        return
    dupes = sorted(i for i, n in Counter(ids).items() if n > 1)
    if dupes:
        fail(errors, f'ids: duplicates found: {dupes}')
    digest = id_digest(binds)
    expected = baseline['id_sha256']
    if digest != expected:
        fail(errors, f'ids: byte-stability digest changed: {digest} '
                     f'(expected {expected})')


def check_dispatch(binds, errors):
    for b in binds:
        bid = b.get('id')
        d = b.get('dispatch')
        kind = (d or {}).get('kind') if isinstance(d, dict) else None
        if kind not in VALID_DISPATCH_KINDS:
            fail(errors, f'{bid}: unknown dispatch kind {kind!r}')
            continue
        if kind == 'command':
            for key in ('id', 'commandId'):
                if key in d and d[key] not in (None, '', bid):
                    fail(errors, f'{bid}: command dispatch {key}={d[key]!r} '
                                 f'conflicts with bind id')
            if not isinstance(d.get('command'), str) or not d['command'].strip():
                fail(errors, f'{bid}: empty command')
        if kind == 'raw' and not (isinstance(d.get('code'), str) and d['code'].strip()):
            fail(errors, f'{bid}: raw dispatch needs code')


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
        if '[' in combo or ']' in combo or '..' in combo:
            fail(errors, f'{bid}: combo {combo!r} contains loop-local/concat artifacts')


def check_labels(binds, errors):
    for b in binds:
        label = b.get('label')
        if not isinstance(label, str) or not label.strip():
            fail(errors, f"{b.get('id')}: missing/empty label")


def combo_tokens(combo):
    """Tokenize a resolved combo for raw-code consistency checks."""
    tokens = set()
    for part in combo.split('+'):
        part = part.strip()
        if part.startswith('code:'):
            tokens.add('code:')
            tokens.add(part[5:])
        else:
            tokens.add(part)
    return tokens


def raw_first_arg(code):
    """Return the source text of the first argument of an hl.bind statement."""
    i = code.find('hl.bind(')
    if i < 0:
        return ''
    i += len('hl.bind(')
    depth = 0
    in_str = False
    esc = False
    for j in range(i, len(code)):
        ch = code[j]
        if in_str:
            if esc:
                esc = False
            elif ch == '\\':
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif ch == ',' and depth == 0:
            return code[i:j]
    return code[i:]


def check_code(binds, errors):
    """Non-raw code must be reproducible; raw code must match its combo."""
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
            if 'hl.bind(' not in code:
                fail(errors, f'{bid}: raw code is not an hl.bind statement')
                continue
            if LOOP_LOCAL_RE.search(code):
                fail(errors, f'{bid}: raw code has unresolved loop local: {code[:90]!r}')
            first = raw_first_arg(code)
            missing = sorted(t for t in combo_tokens(b.get('combo', '')) if t not in first)
            if missing:
                fail(errors, f'{bid}: raw code first arg {first!r} does not contain '
                             f'combo tokens {missing}')
            continue
        try:
            expected = gen.render_bind(b, {}, 'bridge')
        except ValueError as exc:
            fail(errors, f'{bid}: cannot reproduce code: {exc}')
            continue
        if code != expected:
            fail(errors, f'{bid}: non-raw code is not reproducible from dispatch\n'
                         f'    have: {code}\n'
                         f'    want: {expected}')
        if '\n' in code or not code.startswith('hl.bind('):
            fail(errors, f'{bid}: non-raw code is not a standalone statement')


def check_generated(catalog_path, binds, overlay_path, baseline, label, errors):
    """Generate to temp, lint Lua+commands JSON, check parity for a bind set."""
    luac = shutil.which('luac')
    if luac is None:
        fail(errors, 'luac not found on PATH')
        return
    tmp = tempfile.mkdtemp(prefix='keybind-catalog-')
    try:
        main = os.path.join(tmp, 'main.lua')
        custom = os.path.join(tmp, 'custom.lua')
        commands = os.path.join(tmp, 'commands.json')
        cmd = [sys.executable, GENERATOR, '--catalog', catalog_path,
               '--main-out', main, '--custom-out', custom,
               '--commands-out', commands]
        if overlay_path:
            cmd += ['--overlay', overlay_path]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            fail(errors, f'{label}: generator failed ({proc.returncode}): '
                         f'{proc.stderr.strip()}')
            return
        lint = subprocess.run([luac, '-p', main, custom],
                              capture_output=True, text=True)
        if lint.returncode != 0:
            fail(errors, f'{label}: luac -p failed ({lint.returncode}): '
                         f'{lint.stderr.strip()}')

        generated = 0
        lua_text = ''
        for path in (main, custom):
            with open(path, encoding='utf-8') as fh:
                text = fh.read()
            lua_text += text
            generated += sum(1 for line in text.splitlines() if BIND_RE.match(line))
        # The preambles may contain their own hl.bind calls (helpers, rules,
        # or generated detectors). Those are emitted verbatim, not from the
        # catalog bind list, so count them separately for the parity check.
        catalog = load_json(catalog_path)
        preamble_binds = sum(
            1
            for key in ('preamble', 'customPreamble')
            for line in (catalog.get(key) or [])
            if BIND_RE.match(line)
        )
        expected = len(binds) + preamble_binds
        if generated != expected:
            fail(errors, f'{label}: count parity: {len(binds)} binds + '
                         f'{preamble_binds} preamble binds = {expected} but '
                         f'generated Lua has {generated}')

        commands_data = load_json(commands)
        command_ids = {b.get('id') for b in binds
                       if (b.get('dispatch') or {}).get('kind') == 'command'}
        if set(commands_data) != command_ids:
            fail(errors, f'{label}: commands JSON keys != command bind ids '
                         f'(missing={sorted(command_ids - set(commands_data))}, '
                         f'extra={sorted(set(commands_data) - command_ids)})')
        bridge_ids = set(BRIDGE_RE.findall(lua_text))
        if bridge_ids != set(commands_data):
            fail(errors, f'{label}: bridge shortcuts in Lua != commands JSON keys '
                         f'(lua-only={sorted(bridge_ids - set(commands_data))}, '
                         f'json-only={sorted(set(commands_data) - bridge_ids)})')

        # Frozen expectations only apply to the un-merged catalog.
        if not overlay_path:
            if len(binds) != baseline['catalog_binds']:
                fail(errors, f'catalog bind count {len(binds)} != baseline '
                             f'{baseline["catalog_binds"]}')
            runtime = set(baseline['runtime_only_ids'])
            expected_hyprctl = len(binds) - len(runtime)
            if expected_hyprctl != baseline['hyprctl_binds']:
                fail(errors, f'hyprctl parity: {len(binds)} - {len(runtime)} '
                             f'= {expected_hyprctl} != baseline '
                             f'{baseline["hyprctl_binds"]}')
            present = {b.get('id') for b in binds}
            missing = runtime - present
            if missing:
                fail(errors, f'runtime-only ids missing from catalog: {sorted(missing)}')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def check_duplicates(binds, baseline, errors, overlay_active=False):
    actual = find_duplicate_combos(binds)
    if overlay_active:
        # Adds may legitimately share a combo; only report new duplicates as
        # informational (the settings conflict panel handles rebinds).
        return
    allowed = baseline['duplicate_combo_whitelist']
    normal = {c: set(ids) for c, ids in allowed.items()}
    for combo, ids in actual.items():
        want = normal.get(combo)
        if want is None:
            fail(errors, f'duplicate combo not in whitelist: {combo!r} -> {ids}')
        elif set(ids) != want:
            fail(errors, f'duplicate combo {combo!r} ids {ids} != '
                         f'whitelist {sorted(want)}')


def structural_checks(binds, baseline, errors, frozen=True):
    if frozen:
        check_ids(binds, baseline, errors)
    else:
        ids = [b.get('id') for b in binds]
        dupes = sorted(i for i, n in Counter(ids).items() if n > 1)
        if dupes:
            fail(errors, f'merged ids: duplicates found: {dupes}')
    check_dispatch(binds, errors)
    check_combos(binds, errors)
    check_labels(binds, errors)
    check_code(binds, errors)
    check_duplicates(binds, baseline, errors, overlay_active=not frozen)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--catalog', default=DEFAULT_CATALOG,
                    help='catalog JSON (default: repo defaults/hyprland/keybinds.json)')
    ap.add_argument('--overlay', help='user overlay JSON to validate and apply')
    ap.add_argument('--bless', action='store_true',
                    help='rewrite the baseline from the current catalog and exit')
    args = ap.parse_args()

    baseline = load_baseline()
    catalog = load_json(args.catalog)
    binds = catalog.get('binds')
    if not isinstance(binds, list):
        print('FAIL: catalog has no "binds" list', file=sys.stderr)
        return 1
    if args.bless:
        return bless(binds)

    overlay = load_json(args.overlay) if args.overlay else None
    errors = []

    structural_checks(binds, baseline, errors, frozen=True)
    check_generated(args.catalog, binds, None, baseline, 'catalog', errors)

    merged = binds
    if args.overlay:
        if HERE not in sys.path:
            sys.path.insert(0, HERE)
        import generate_keybinds as gen  # noqa: WPS433 (local by design)
        ov_errors = gen.validate_overlay(catalog, overlay)
        for err in ov_errors:
            fail(errors, f'overlay: {err}')
        if not ov_errors:
            merged = gen.merged_binds(catalog, overlay)
            structural_checks(merged, baseline, errors, frozen=False)
            check_generated(args.catalog, merged, args.overlay, baseline,
                            'merged', errors)

    if errors:
        print(f'FAIL: {len(errors)} validation error(s):', file=sys.stderr)
        for err in errors:
            print(f'  - {err}', file=sys.stderr)
        return 1

    counts = Counter(b.get('dispatch', {}).get('kind') for b in merged)
    suffix = f', overlay applied ({len(merged)} binds)' if args.overlay else ''
    print(f'OK: {len(binds)} catalog binds '
          f'({counts["raw"]} raw, {len(merged) - counts["raw"]} normalized), '
          f'{baseline["hyprctl_binds"]} hyprctl-visible; '
          f'ids unique + byte-stable; combos/dispatch/labels/code valid; '
          f'generated Lua + commands JSON pass lint/parity; '
          f'duplicates whitelisted{suffix}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
