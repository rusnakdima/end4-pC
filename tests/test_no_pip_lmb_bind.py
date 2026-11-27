import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "defaults/hyprland/keybinds.json"
GENERATOR = ROOT / "scripts/hyprland/generate_keybinds.py"


class NoPipLmbBindTest(unittest.TestCase):
    def test_preamble_has_no_pip_lmb_block(self):
        preamble = "\n".join(json.loads(CATALOG.read_text())["preamble"])
        for needle in (
            "end4pcPipLmbBound",
            'hl.on("window.active"',
            'w.title == "Picture-in-Picture"',
            'hl.bind("mouse:272"',
            'hl.unbind("mouse:272")',
            "drag_threshold",
        ):
            self.assertNotIn(needle, preamble, needle)

    def test_generator_emits_no_plain_lmb_bind_and_keeps_super_lmb(self):
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / "main.lua"
            custom = Path(tmp) / "custom.lua"
            subprocess.run(
                [
                    "python3", str(GENERATOR),
                    "--catalog", str(CATALOG),
                    "--main-out", str(main),
                    "--custom-out", str(custom),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            lua = main.read_text() + custom.read_text()
        self.assertEqual(lua.count('hl.bind("mouse:272"'), 0)
        self.assertEqual(lua.count('hl.unbind("mouse:272"'), 0)
        self.assertEqual(lua.count('hl.bind("SUPER + mouse:272"'), 1)


if __name__ == "__main__":
    unittest.main()
