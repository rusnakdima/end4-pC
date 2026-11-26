import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "defaults/hyprland/keybinds.json"
# The dynamic bind is nested in an if block, so compare stripped lines.


class PipLmbBindTest(unittest.TestCase):
    def test_preamble_contains_pip_lmb_block(self):
        preamble = "\n".join(json.loads(CATALOG.read_text())["preamble"])
        for needle in (
            'hl.on("window.active", function(w)',
            'w.class == "zen"',
            'w.title == "Picture-in-Picture"',
            'hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true, non_consuming = true })',
            'hl.unbind("mouse:272")',
        ):
            self.assertIn(needle, preamble, needle)

    def test_pip_bind_does_not_change_global_drag_threshold(self):
        preamble = "\n".join(json.loads(CATALOG.read_text())["preamble"])
        self.assertNotIn('drag_threshold', preamble)

    def test_generator_emits_exactly_one_pip_lmb_bind(self):
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / "main.lua"
            custom = Path(tmp) / "custom.lua"
            subprocess.run([
                "python3", str(ROOT / "scripts/hyprland/generate_keybinds.py"),
                "--catalog", str(CATALOG),
                "--main-out", str(main), "--custom-out", str(custom),
            ], check=True, capture_output=True, text=True)
            lua = (main.read_text() + custom.read_text()).splitlines()
        binds = [line.strip() for line in lua if line.strip().startswith('hl.bind("mouse:272"')]
        self.assertEqual(len(binds), 1, "expected one plain LMB bind")
        self.assertIn('hl.dsp.window.drag()', binds[0])
        self.assertIn('mouse = true', binds[0])
        self.assertIn('non_consuming = true', binds[0], "PiP clicks must reach the app")
        super_binds = [line.strip() for line in lua if line.strip().startswith('hl.bind("SUPER + mouse:272"')]
        self.assertEqual(len(super_binds), 1, "SUPER+LMB must remain bound")

    def test_pip_block_unbinds_only_after_binding(self):
        preamble = "\n".join(json.loads(CATALOG.read_text())["preamble"])
        bound = preamble.index('hl.bind("mouse:272"')
        unbound = preamble.index('hl.unbind("mouse:272")')
        self.assertLess(bound, unbound)
        self.assertEqual(preamble.count('hl.bind("mouse:272"'), 1)
        self.assertEqual(preamble.count('hl.unbind("mouse:272")'), 1)
