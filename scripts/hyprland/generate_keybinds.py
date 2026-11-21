#!/usr/bin/env python3
"""Generate the live Hyprland keybind Lua files from the JSON catalog + user overlay.

Usage:
  generate_keybinds.py --catalog FILE [--overlay FILE] \\
      --main-out FILE --custom-out FILE [--commands-out FILE]

The catalog is the frozen default list (defaults/hyprland/keybinds.json).
The overlay (optional) contains only user changes, keyed by bind id:
  { "overrides": { "<id>": { "combo", "description", "dispatch", "options", "enabled" } },
    "adds": [ { "id", "category", "combo", "description", "dispatch", "options" } ],
    "disabled": ["<id>", ...] }

Nothing in the catalog is ever modified by this script.
"""
import argparse, json, os, re, sys
from collections import OrderedDict

def lua_string(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + '"'

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
            if re.match(r'^[A-Za-z_]\w*$', key):
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

def dispatch_expr(d, bind_id=None):
    """Return a Lua expression producing the dispatcher for a normalized dispatch spec."""
    kind = d.get('kind')
    if kind == 'raw':
        return None  # caller emits the full statement
    if kind == 'command':
        cid = d.get('id') or d.get('commandId') or bind_id or ''
        if not cid:
            raise ValueError(f'command bind without id: {d}')
        return f'hl.dsp.global({lua_string("quickshell:runCommand:" + cid)})'
    if kind == 'unknown':
        return None
    arg = arg_plain(d.get('arg', {'kind': 'nil'}))
    if arg is None:
        return f'hl.dsp.{kind}()'
    return f'hl.dsp.{kind}({lua_value(arg)})'

def render_bind(b, commands, exec_mode='bridge'):
    d = b.get('dispatch', {})
    if d.get('kind') == 'raw':
        return b.get('code', '')
    if d.get('kind') == 'command' and exec_mode == 'legacy':
        # Phase-1 fidelity mode: emit the original statement verbatim.
        return b.get('code', '')
    expr = dispatch_expr(d, b.get('id'))
    if expr is None:
        return b.get('code', '')
    if d.get('kind') == 'command':
        commands[b['id']] = {
            'command': d.get('command', ''),
            'description': b.get('description', '') or b.get('id', ''),
            'category': b.get('category', ''),
        }
    opts = dict(b.get('options') or {})
    if b.get('description'):
        opts['description'] = b['description']
    optstr = 'nil'
    if opts:
        optstr = lua_value(opts)
    return f'hl.bind({lua_string(b["combo"])}, {expr}, {optstr})'

def load_json(path):
    if not path or not os.path.exists(path):
        return None
    return json.load(open(path), object_pairs_hook=OrderedDict)

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
            for key in ('combo', 'description', 'category', 'dispatch', 'options'):
                if key in ov:
                    nb[key] = ov[key]
            if ov.get('enabled') is False:
                continue
        binds.append(nb)
    for a in adds:
        nb = dict(a)
        nb.setdefault('options', {})
        nb.setdefault('description', '')
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
    overlay = load_json(args.overlay)
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

    with open(args.main_out, 'w') as f:
        f.write(render_set('main', catalog.get('preamble', [])))
    with open(args.custom_out, 'w') as f:
        f.write(render_set('custom', catalog.get('customPreamble', [])))
    if args.commands_out:
        with open(args.commands_out, 'w') as f:
            json.dump(commands, f, indent=1, ensure_ascii=False)

    print(f'generated {len(binds)} binds; {len(commands)} command bridges')

if __name__ == '__main__':
    main()
