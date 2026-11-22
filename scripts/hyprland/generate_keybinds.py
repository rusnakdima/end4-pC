#!/usr/bin/env python3
"""Generate the live Hyprland keybind Lua files from the JSON catalog + user overlay.

Usage:
  generate_keybinds.py --catalog FILE [--overlay FILE] \\
      --main-out FILE --custom-out FILE [--commands-out FILE]
      [--exec-mode bridge|legacy]

The catalog is the frozen default list (defaults/hyprland/keybinds.json).
The overlay (optional) contains only user changes, keyed by bind id:
  { "overrides": { "<id>": { "combo", "description", "dispatch", "options", "enabled" } },
    "adds": [ { "id", "category", "combo", "description", "dispatch", "options" } ],
    "disabled": ["<id>", ...] }

Nothing in the catalog is ever modified by this script. Overlay data is
validated before generation; invalid overlay entries are rejected with a
clear error instead of emitting broken Lua.

All output files are written atomically (temp file + os.replace) so an
interrupted run can never leave a truncated live Lua file behind.
"""
import argparse, json, os, re, sys, tempfile
from collections import OrderedDict

VALID_DISPATCH_KINDS = frozenset({
    'raw', 'command', 'unknown',
    'global', 'focus', 'layout',
    'window.move', 'window.drag', 'window.resize', 'window.fullscreen',
    'window.fullscreen_state', 'window.close', 'window.float', 'window.pin',
    'workspace.toggle_special',
})
MODIFIERS = frozenset({'SUPER', 'SHIFT', 'CTRL', 'ALT', 'META'})
KEY_RE = re.compile(r'^[A-Za-z0-9_:.\-]+$')
IDENT_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


# --- Lua literal helpers -----------------------------------------------------
def lua_string(s):
    out = []
    for ch in str(s):
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif ord(ch) < 0x20 or ord(ch) == 0x7f:
            # Lua decimal escape; keeps the source ASCII and NUL-safe.
            out.append('\\%03d' % ord(ch))
        else:
            out.append(ch)
    return '"' + ''.join(out) + '"'


def lua_value(v, indent=0):
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, dict):
        parts = []
        for k, val in v.items():
            key = str(k)
            if IDENT_RE.match(key):
                parts.append(f'{key} = {lua_value(val, indent + 1)}')
            else:
                parts.append(f'[{lua_value(key, indent + 1)}] = {lua_value(val, indent + 1)}')
        return '{ ' + ', '.join(parts) + ' }'
    if isinstance(v, list):
        return '{ ' + ', '.join(lua_value(x, indent + 1) for x in v) + ' }'
    return lua_string(str(v))


def arg_plain(a):
    if not isinstance(a, dict):
        return None
    k = a.get('kind')
    if k == 'nil':
        return None
    if k in ('string', 'number', 'boolean'):
        return a.get('value')
    if k == 'table':
        return {key: arg_plain(val) for key, val in a.get('value', {}).items()}
    return None


# --- dispatch rendering ------------------------------------------------------
def command_id_of(d, bind_id):
    """Return the single authoritative id for a command bind's bridge shortcut.

    The emitted Lua and the commands JSON must use the SAME id. A dispatch
    carrying a conflicting id is rejected: silently preferring it would point
    the Lua at a shortcut the bridge never registers (a dead bind).
    """
    for key in ('id', 'commandId'):
        if key in d and d[key] not in (None, '', bind_id):
            raise ValueError(
                f'command dispatch {key}={d[key]!r} conflicts with bind id '
                f'{bind_id!r}; remove it or set it to the bind id'
            )
    if not bind_id:
        raise ValueError('command bind without id')
    return bind_id


def dispatch_expr(d, bind_id=None):
    """Return a Lua expression producing the dispatcher for a normalized spec.

    Returns None for `raw` (caller emits the stored statement) and for the
    legacy `unknown` kind (caller falls back to the stored code).
    """
    if not isinstance(d, dict):
        raise ValueError(f'invalid dispatch spec: {d!r}')
    kind = d.get('kind')
    if kind in ('raw', 'unknown'):
        return None
    if kind == 'command':
        cid = command_id_of(d, bind_id)
        return f'hl.dsp.global({lua_string("quickshell:runCommand:" + cid)})'
    if kind not in VALID_DISPATCH_KINDS:
        raise ValueError(f'unknown dispatch kind {kind!r} for bind {bind_id!r}')
    arg = arg_plain(d.get('arg', {'kind': 'nil'}))
    if arg is None:
        return f'hl.dsp.{kind}()'
    return f'hl.dsp.{kind}({lua_value(arg)})'


def render_bind(b, commands, exec_mode='bridge'):
    """Render one bind statement. For command binds, also populate `commands`."""
    d = b.get('dispatch')
    if not isinstance(d, dict):
        raise ValueError(f"{b.get('id')}: missing dispatch spec")
    kind = d.get('kind')
    if kind == 'raw':
        return b.get('code', '')
    if kind == 'command' and exec_mode == 'legacy':
        # Phase-1 fidelity mode: emit the original statement verbatim.
        return b.get('code', '')
    expr = dispatch_expr(d, b.get('id'))
    if expr is None:
        return b.get('code', '')
    if kind == 'command':
        cid = command_id_of(d, b.get('id'))
        commands[cid] = {
            'command': d.get('command', ''),
            'description': b.get('description', '') or b.get('label', '') or b.get('id', ''),
            'category': b.get('category', ''),
        }
    opts = dict(b.get('options') or {})
    if b.get('description'):
        opts['description'] = b['description']
    optstr = 'nil'
    if opts:
        optstr = lua_value(opts)
    return f'hl.bind({lua_string(b["combo"])}, {expr}, {optstr})'


# --- I/O ---------------------------------------------------------------------
def load_json(path):
    if not path or not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as fh:
        return json.load(fh, object_pairs_hook=OrderedDict)


def write_text(path, text):
    """Atomically write text to path, preserving an existing file's mode."""
    directory = os.path.dirname(os.path.abspath(path)) or '.'
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.keybind-gen-', dir=directory, text=True)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as fh:
            fh.write(text)
        if os.path.exists(path):
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_json(path, data):
    write_text(path, json.dumps(data, indent=1, ensure_ascii=False) + '\n')


# --- overlay validation ------------------------------------------------------
def parse_combo(combo):
    """Return (modifiers, key) or raise ValueError. Mirrors the validator."""
    if not isinstance(combo, str) or not combo.strip():
        raise ValueError('empty combo')
    parts = [p.strip() for p in combo.split('+')]
    if any(not p for p in parts):
        raise ValueError(f'empty combo token in {combo!r}')
    for part in parts:
        if not KEY_RE.fullmatch(part):
            raise ValueError(f'unparseable combo token {part!r} in {combo!r}')
    keys = [p for p in parts if p.upper() not in MODIFIERS]
    if len(keys) != 1:
        raise ValueError(f'combo {combo!r} has {len(keys)} key tokens (expected 1)')
    return [p.upper() for p in parts if p.upper() in MODIFIERS], keys[0]


def validate_dispatch(d, bid):
    if not isinstance(d, dict):
        raise ValueError('missing dispatch spec')
    kind = d.get('kind')
    if kind not in VALID_DISPATCH_KINDS:
        raise ValueError(f'unknown dispatch kind {kind!r}')
    if kind == 'command':
        command_id_of(d, bid)  # raises on conflicting/empty id
        if not isinstance(d.get('command'), str) or not d['command'].strip():
            raise ValueError('command is empty')
    if kind == 'raw' and not (isinstance(d.get('code'), str) and d['code'].strip()):
        raise ValueError('raw dispatch needs code')


def validate_overlay(catalog, overlay):
    """Return a list of human-readable errors; empty means the overlay is safe."""
    errors = []
    if overlay is None:
        return errors
    if not isinstance(overlay, dict):
        return ['overlay must be a JSON object']
    catalog_ids = {b.get('id') for b in catalog.get('binds', [])}
    seen_ids = set(catalog_ids)

    overrides = overlay.get('overrides', {})
    if not isinstance(overrides, dict):
        errors.append('overrides must be an object')
    else:
        for bid, ov in overrides.items():
            if bid not in catalog_ids:
                errors.append(f'overrides: unknown bind id {bid!r}')
                continue
            if not isinstance(ov, dict):
                errors.append(f'overrides.{bid}: must be an object')
                continue
            allowed = {'combo', 'description', 'category', 'dispatch', 'options', 'enabled', 'label'}
            for key in ov:
                if key not in allowed:
                    errors.append(f'overrides.{bid}: unsupported field {key!r}')
            if 'combo' in ov:
                try:
                    parse_combo(ov['combo'])
                except ValueError as exc:
                    errors.append(f'overrides.{bid}: combo: {exc}')
            if 'dispatch' in ov:
                try:
                    validate_dispatch(ov['dispatch'], bid)
                except ValueError as exc:
                    errors.append(f'overrides.{bid}: dispatch: {exc}')
            if 'enabled' in ov and not isinstance(ov['enabled'], bool):
                errors.append(f'overrides.{bid}: enabled must be boolean')

    adds = overlay.get('adds', [])
    if not isinstance(adds, list):
        errors.append('adds must be a list')
    else:
        for i, add in enumerate(adds):
            if not isinstance(add, dict):
                errors.append(f'adds[{i}]: must be an object')
                continue
            bid = add.get('id')
            if not isinstance(bid, str) or not bid.strip():
                errors.append(f'adds[{i}]: missing/empty id')
            elif bid in seen_ids:
                errors.append(f'adds[{i}]: duplicate id {bid!r}')
            else:
                seen_ids.add(bid)
            if 'combo' not in add:
                errors.append(f'adds[{i}]: missing combo')
            else:
                try:
                    parse_combo(add['combo'])
                except ValueError as exc:
                    errors.append(f'adds[{i}]: combo: {exc}')
            if 'dispatch' not in add:
                errors.append(f'adds[{i}]: missing dispatch')
            else:
                try:
                    validate_dispatch(add['dispatch'], bid)
                except ValueError as exc:
                    errors.append(f'adds[{i}]: dispatch: {exc}')

    disabled = overlay.get('disabled', [])
    if not isinstance(disabled, list):
        errors.append('disabled must be a list')
    else:
        for bid in disabled:
            if bid not in catalog_ids:
                errors.append(f'disabled: unknown bind id {bid!r}')

    unknown = set(overlay) - {'overrides', 'adds', 'disabled'}
    for key in sorted(unknown):
        errors.append(f'unsupported top-level overlay field {key!r}')
    return errors


# --- merge -------------------------------------------------------------------
def merged_binds(catalog, overlay):
    binds = []
    overrides = (overlay or {}).get('overrides', {})
    adds = (overlay or {}).get('adds', [])
    disabled = set((overlay or {}).get('disabled', []))
    for b in catalog['binds']:
        if b['id'] in disabled:
            continue
        nb = dict(b)
        ov = overrides.get(b['id'])
        if ov:
            for key in ('combo', 'description', 'category', 'dispatch', 'options', 'label'):
                if key in ov:
                    nb[key] = ov[key]
            if ov.get('enabled') is False:
                continue
        binds.append(nb)
    for a in adds:
        nb = dict(a)
        nb.setdefault('options', {})
        nb.setdefault('description', '')
        nb.setdefault('label', '')
        nb.setdefault('category', '')
        nb.setdefault('source', 'custom')
        binds.append(nb)
    return binds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--catalog', required=True)
    ap.add_argument('--overlay')
    ap.add_argument('--main-out', required=True)
    ap.add_argument('--custom-out', required=True)
    ap.add_argument('--commands-out')
    ap.add_argument('--exec-mode', choices=['bridge', 'legacy'], default='bridge')
    args = ap.parse_args()

    catalog = load_json(args.catalog)
    if not isinstance(catalog, dict) or not isinstance(catalog.get('binds'), list):
        print('error: catalog has no "binds" list', file=sys.stderr)
        return 2
    overlay = load_json(args.overlay)
    errors = validate_overlay(catalog, overlay)
    if errors:
        print(f'error: {len(errors)} overlay validation error(s):', file=sys.stderr)
        for err in errors:
            print(f'  - {err}', file=sys.stderr)
        return 2

    try:
        binds = merged_binds(catalog, overlay)
        commands = OrderedDict()

        def render_set(source, preamble):
            lines = list(preamble or [])
            lines.append('')
            lines.append('-- === generated from JSON catalog — do not edit by hand ===')
            for b in binds:
                if b.get('source') != source:
                    continue
                stmt = render_bind(b, commands, args.exec_mode)
                if stmt:
                    lines.append(stmt)
            return '\n'.join(lines).rstrip() + '\n'

        main_lua = render_set('main', catalog.get('preamble', []))
        custom_lua = render_set('custom', catalog.get('customPreamble', []))
    except ValueError as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 2

    write_text(args.main_out, main_lua)
    write_text(args.custom_out, custom_lua)
    if args.commands_out:
        write_json(args.commands_out, commands)

    print(f'generated {len(binds)} binds; {len(commands)} command bridges')
    return 0


if __name__ == '__main__':
    sys.exit(main())
