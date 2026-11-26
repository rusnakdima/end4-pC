"""Unit tests for the read-only keybind audit (no live Hyprland calls)."""
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT_PATH = ROOT / 'scripts/diagnostics/keybind-audit.py'


def load_audit():
    spec = importlib.util.spec_from_file_location('keybind_audit', AUDIT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CATALOG = {'binds': [
    {'id': 'plain', 'combo': 'SUPER + A', 'description': 'Focus window',
     'dispatch': {'kind': 'focus', 'target': 'window'}},
    {'id': 'over', 'combo': 'SUPER + B', 'description': 'Toggle foo',
     'dispatch': {'kind': 'global', 'name': 'quickshell:foo'}},
    {'id': 'off', 'combo': 'SUPER + C', 'description': 'Disabled one',
     'dispatch': {'kind': 'command', 'id': 'off', 'command': 'true'}},
    {'id': 'bind', 'combo': 'SUPER + SUPER_L', 'description': 'Tap launcher',
     'options': {'release': True},
     'dispatch': {'kind': 'command', 'id': 'bind', 'command': 'true'}},
    {'id': 'lock', 'combo': 'SUPER + L', 'description': 'Session: Lock screen',
     'dispatch': {'kind': 'command', 'id': 'lock', 'command': 'true'}},
]}

OVERLAY = {'overrides': {'over': {'combo': 'SUPER + D'}}, 'disabled': ['off']}

LIVE_BINDS = [
    {'modmask': 64, 'key': 'A'},
    {'modmask': 64, 'key': 'D'},
    {'modmask': 64, 'key': 'SUPER_L'},
    {'modmask': 64, 'key': 'L'},
]


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(AUDIT_PATH.exists(), 'audit script not implemented yet')
        self.ka = load_audit()

    def test_classify_binds_marks_overrides_disabled_and_runtime_only(self):
        result = self.ka.classify_binds(CATALOG, OVERLAY, LIVE_BINDS)
        self.assertEqual(result['over']['combo'], 'SUPER + D')
        self.assertEqual(result['off']['category'], 'disabled')
        self.assertEqual(result['bind']['category'], 'dead-by-design')
        self.assertEqual(result['plain']['category'], 'verified-structural')
        report = self.ka.render_report({'classified': result, 'issues': []})
        for bid in ('plain', 'over', 'off', 'bind', 'lock'):
            self.assertEqual(report.count(bid), 1, f'{bid} missing/duplicated in report')

    def test_audit_global_targets_reports_unregistered_target(self):
        lua = 'hl.bind("SUPER + D", hl.dsp.global("quickshell:foo"), nil)\n'
        self.assertEqual(self.ka.audit_global_targets(lua, {'quickshell:foo'}), [])
        issues = self.ka.audit_global_targets(lua, set())
        self.assertTrue(any('quickshell:foo' in i for i in issues), issues)

    def test_audit_commands_reports_syntax_binary_and_ipc_failures(self):
        commands = {
            'good': {'command': 'true'},
            'bad': {'command': 'if then'},
            'missing': {'command': 'nonexistent-binary-xyz --flag'},
            'ipc': {'command': 'qs -c end4-pC ipc call targetX missingMethod'},
        }
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, 'services'))
            with open(os.path.join(tmp, 'services', 'Fake.qml'), 'w') as f:
                f.write('IpcHandler { target: "targetX"; function existingMethod() {} }\n')
            issues = self.ka.audit_commands(commands, home=tmp, repo=tmp)
        self.assertTrue(any('bad' in i and 'syntax' in i for i in issues), issues)
        self.assertTrue(any('missing' in i and 'executable' in i for i in issues), issues)
        self.assertTrue(any('ipc' in i and 'missingMethod' in i for i in issues), issues)
        self.assertFalse(any('good' in i for i in issues), issues)

    def test_audit_live_binds_reports_missing_effective_combo(self):
        effective = [{'id': 'x', 'combo': 'SUPER + A',
                      'dispatch': {'kind': 'focus', 'target': 'window'}}]
        issues = self.ka.audit_live_binds(effective, [])
        self.assertTrue(any('x' in i and 'SUPER + A' in i for i in issues), issues)
        self.assertEqual(self.ka.audit_live_binds([], LIVE_BINDS), [])

    def test_combo_key_matches_keycode_binds(self):
        self.assertEqual(self.ka.combo_key('SUPER + code:82'), (64, 82))
        self.assertEqual(self.ka.live_key({'modmask': 64, 'key': '', 'keycode': 82}), (64, 82))
        effective = [{'id': 'code-bind', 'combo': 'SUPER + code:82',
                      'dispatch': {'kind': 'raw', 'code': 'x'}}]
        live = [{'modmask': 64, 'key': '', 'keycode': 82}]
        self.assertEqual(self.ka.audit_live_binds(effective, live), [])

    def test_classify_binds_includes_overlay_additions(self):
        overlay = {'adds': [{'id': 'added', 'combo': 'SUPER + E',
                             'description': 'Added one',
                             'dispatch': {'kind': 'command', 'id': 'added',
                                          'command': 'true'}}]}
        live = LIVE_BINDS + [{'modmask': 64, 'key': 'E'}]
        result = self.ka.classify_binds(CATALOG, overlay, live)
        self.assertIn('added', result)
        self.assertEqual(result['added']['category'], 'verified-structural')

    def test_classify_binds_marks_session_and_reload_binds_unsafe(self):
        catalog = {'binds': [
            {'id': 'reload', 'combo': 'CTRL + SUPER + R',
             'description': 'Shell: Reload theme',
             'dispatch': {'kind': 'raw', 'code': 'x'}},
        ] + CATALOG['binds']}
        result = self.ka.classify_binds(catalog, OVERLAY, LIVE_BINDS)
        self.assertEqual(result['reload']['category'], 'unsafe-to-test')
        self.assertEqual(result['lock']['category'], 'unsafe-to-test')


if __name__ == '__main__':
    unittest.main()
