#!/usr/bin/env python3
"""Read-only audit of end4-pC keybinds: catalog -> overlay -> generated -> live.

This script never activates a bind, reloads Hyprland, or manages processes.
It only reads JSON/Lua files and queries hyprctl for loaded binds, registered
global shortcuts, and config errors.
"""
import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'scripts/hyprland'))
import generate_keybinds as gen  # noqa: E402

MODMASK = {'SHIFT': 1, 'CTRL': 4, 'ALT': 8, 'SUPER': 64, 'META': 16}
RUNTIME_ONLY_IDS = frozenset({'bind', 'bind-2'})
UNSAFE_TOKENS = (
    'lock screen', 'lock session', 'shutdown', 'reboot', 'poweroff',
    'power off', 'sleep', 'suspend', 'hibernate', 'logout', 'log out',
    'reload theme', 'reload shell',
)
SHELL_BUILTINS = frozenset({'true', 'false', 'command', 'echo', 'printf', 'test', '['})


def combo_key(combo):
    """Map a catalog combo string to Hyprland's (modmask, key) pair."""
    mods, key = gen.parse_combo(combo)
    mask = sum(MODMASK.get(m, 0) for m in mods)
    if key.lower().startswith('code:'):
        return mask, int(key.split(':', 1)[1])
    return mask, key.upper()


def live_key(bind):
    mask = int(bind.get('modmask', 0))
    key = str(bind.get('key', ''))
    if not key and bind.get('keycode'):
        return mask, int(bind['keycode'])
    return mask, key.upper()


def _is_unsafe(bind):
    text = (bind.get('description') or '').lower()
    return any(token in text for token in UNSAFE_TOKENS)


def classify_binds(catalog, overlay, live_binds, runtime_only_ids=RUNTIME_ONLY_IDS):
    """Classify every catalog id (and overlay addition) without executing binds.

    ``live_binds`` is the list from ``hyprctl binds -j``; pass None to skip the
    loaded-combo check entirely (offline mode).
    """
    effective = gen.merged_binds(catalog, overlay)
    catalog_ids = {b['id'] for b in catalog['binds']}
    live_keys = {live_key(b) for b in live_binds} if live_binds is not None else None
    overrides = (overlay or {}).get('overrides', {})
    disabled = set((overlay or {}).get('disabled', []))
    result = {}
    for bind in catalog['binds'] + [b for b in effective if b['id'] not in catalog_ids]:
        bid = bind['id']
        combo = overrides.get(bid, {}).get('combo', bind.get('combo', ''))
        kind = (bind.get('dispatch') or {}).get('kind', 'unknown')
        if (bid in disabled or overrides.get(bid, {}).get('enabled') is False
                or bind.get('enabled') is False):
            category = 'disabled'
        elif bid in runtime_only_ids or (bind.get('options') or {}).get('release') is True:
            category = 'dead-by-design'
        elif _is_unsafe(bind):
            category = 'unsafe-to-test'
        elif live_keys is not None and combo_key(combo) not in live_keys:
            category = 'not-loaded'
        else:
            category = 'verified-structural'
        result[bid] = {
            'id': bid,
            'combo': combo,
            'category': category,
            'dispatch_kind': kind,
        }
    return result


def audit_global_targets(lua_text, registered):
    """Report global-shortcut dispatch targets that are not registered."""
    issues = []
    for target in sorted(set(re.findall(r'hl\.dsp\.global\(\s*"([^"]+)"\s*\)', lua_text or ''))):
        if target not in registered:
            issues.append(f'unregistered global shortcut target: {target}')
    return issues


def _index_ipc_methods(repo):
    """Index IpcHandler targets and their functions from QML source."""
    index = {}
    for path in Path(repo).rglob('*.qml'):
        try:
            text = path.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        for target in set(re.findall(r'target:\s*"([^"]+)"', text)):
            index.setdefault(target, set()).update(
                re.findall(r'function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', text))
    return index


def audit_commands(commands, home, repo):
    """Statically validate command bridges: syntax, binaries, scripts, IPC."""
    issues = []
    ipc_index = _index_ipc_methods(repo)
    for cid, entry in (commands or {}).items():
        command = entry.get('command', '')
        expanded = (command.replace('$HOME', str(home))
                    .replace('$qsConfig', 'end4-pC')
                    .replace('$qsScripts', str(Path(home) / '.config/hypr/hyprland/scripts'))
                    .replace('$qsIpcCall', 'qs -c end4-pC ipc call'))
        syntax = subprocess.run(['bash', '-n'], input=expanded,
                                text=True, capture_output=True, check=False)
        if syntax.returncode != 0:
            issues.append(f'{cid}: command syntax error: {syntax.stderr.strip()[:120]}')
        for segment in re.split(r'\|\||&&|\|', expanded):
            try:
                tokens = shlex.split(segment.strip())
            except ValueError:
                continue
            if not tokens:
                continue
            exe = tokens[0]
            if exe.startswith('~'):
                exe = str(Path(home) / exe[2:])
            if exe in SHELL_BUILTINS:
                continue
            if exe.startswith('/'):
                found = os.path.exists(exe)
            else:
                found = shutil.which(exe) is not None
            if not found:
                issues.append(f'{cid}: missing executable: {exe}')
        for target, method in re.findall(r'ipc\s+call\s+([\w-]+)\s+([\w-]+)', expanded):
            if target == 'TEST_ALIVE':
                continue
            if target not in ipc_index:
                issues.append(f'{cid}: unknown IPC target: {target}')
            elif method not in ipc_index[target]:
                issues.append(f'{cid}: unknown IPC method: {target}.{method}')
    return issues


def audit_live_binds(effective, live_binds):
    """Report effective combos that Hyprland did not load."""
    if live_binds is None:
        return []
    live_keys = {live_key(b) for b in live_binds}
    issues = []
    for bind in effective:
        if bind['id'] in RUNTIME_ONLY_IDS:
            continue
        combo = bind.get('combo', '')
        try:
            key = combo_key(combo)
        except ValueError:
            issues.append(f"{bind['id']}: unparseable combo: {combo}")
            continue
        if key not in live_keys:
            issues.append(f"{bind['id']}: combo not loaded by Hyprland: {combo}")
    return issues


def render_report(result):
    classified = result.get('classified', {})
    counts = {}
    for info in classified.values():
        counts[info['category']] = counts.get(info['category'], 0) + 1
    lines = [f'Shortcut catalog audit (read-only) — {len(classified)} ids']
    for category in ('verified-structural', 'disabled', 'dead-by-design',
                     'unsafe-to-test', 'not-loaded'):
        if counts.get(category):
            lines.append(f'  {category}: {counts[category]}')
    lines.append('Binds:')
    for bid, info in sorted(classified.items()):
        lines.append(f'  {bid}: {info["combo"]} [{info["category"]}] {info["dispatch_kind"]}')
    issues = result.get('issues', [])
    lines.append(f'Issues: {len(issues)}')
    for issue in issues:
        lines.append(f'  - {issue}')
    return '\n'.join(lines)


def _read_json(path, issues):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError) as exc:
        issues.append(f'cannot read {path}: {exc}')
        return None


def _read_text(path, issues):
    try:
        return Path(path).read_text(encoding='utf-8')
    except OSError as exc:
        issues.append(f'cannot read {path}: {exc}')
        return ''


def _hyprctl(args, issues):
    try:
        proc = subprocess.run(['hyprctl'] + args, text=True, capture_output=True,
                              check=False, timeout=10)
        return proc.stdout
    except (OSError, subprocess.SubprocessError) as exc:
        issues.append(f'hyprctl {args[0]} unavailable: {exc}')
        return ''


def audit(args=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', default=str(REPO / 'defaults/hyprland/keybinds.json'))
    parser.add_argument('--overlay', default=str(Path.home() / '.config/hypr/custom/keybind-overlay.json'))
    parser.add_argument('--main-lua', default=str(Path.home() / '.config/hypr/hyprland/keybinds.lua'))
    parser.add_argument('--custom-lua', default=str(Path.home() / '.config/hypr/custom/keybinds.lua'))
    parser.add_argument('--commands', default=str(Path.home() / '.config/quickshell/end4-pC/state/generated-commands.json'))
    parser.add_argument('--repo', default=str(REPO))
    parser.add_argument('--home', default=str(Path.home()))
    parser.add_argument('--skip-live', action='store_true', help='offline: do not query hyprctl')
    opts = parser.parse_args(args)

    issues = []
    catalog = _read_json(opts.catalog, issues)
    overlay = _read_json(opts.overlay, issues) or {}
    commands = _read_json(opts.commands, issues) or {}
    if catalog is None:
        print('cannot audit without a catalog', file=sys.stderr)
        return 2

    if opts.skip_live:
        live_binds = None
        registered = set()
    else:
        try:
            live_binds = json.loads(_hyprctl(['binds', '-j'], issues) or '[]')
        except ValueError:
            live_binds = []
            issues.append('hyprctl binds -j returned invalid JSON')
        registered = set()
        for line in _hyprctl(['globalshortcuts'], issues).splitlines():
            if ' -> ' in line:
                registered.add(line.split(' -> ', 1)[0].strip())
        errors = _hyprctl(['configerrors'], issues).strip()
        if errors:
            issues.append(f'hyprctl configerrors: {errors[:200]}')

    lua = (_read_text(opts.main_lua, issues) + '\n' + _read_text(opts.custom_lua, issues))
    issues.extend(audit_global_targets(lua, registered))
    for cid in commands:
        target = f'quickshell:runCommand:{cid}'
        if not opts.skip_live and target not in registered:
            issues.append(f'unregistered command bridge: {target}')
    issues.extend(audit_commands(commands, opts.home, opts.repo))

    effective = gen.merged_binds(catalog, overlay)
    issues.extend(audit_live_binds(effective, live_binds))
    classified = classify_binds(catalog, overlay, live_binds)
    print(render_report({'classified': classified, 'issues': issues}))
    return 1 if issues else 0


if __name__ == '__main__':
    sys.exit(audit())
