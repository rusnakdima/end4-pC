import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class RecordBindTest(unittest.TestCase):
    def test_record_bind_is_unique_and_wired(self):
        catalog = json.loads((ROOT / "defaults/hyprland/keybinds.json").read_text())
        matches = [b for b in catalog["binds"] if b["combo"] == "SUPER + SHIFT + R"]
        self.assertEqual(len(matches), 1, "expected exactly one SUPER + SHIFT + R bind")
        bind = matches[0]
        self.assertEqual(bind["dispatch"]["kind"], "global")
        self.assertEqual(bind["dispatch"]["arg"]["value"], "quickshell:regionRecord")
        self.assertEqual(bind["id"], "utilities-17")

    def test_generator_emits_region_record_bind(self):
        catalog = ROOT / "defaults/hyprland/keybinds.json"
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / "main.lua"
            custom = Path(tmp) / "custom.lua"
            subprocess.run([
                "python3", str(ROOT / "scripts/hyprland/generate_keybinds.py"),
                "--catalog", str(catalog),
                "--main-out", str(main), "--custom-out", str(custom),
            ], check=True, capture_output=True, text=True)
            lua = (main.read_text() + custom.read_text()).splitlines()
        active = [
            line for line in lua
            if line.startswith('hl.bind("SUPER + SHIFT + R", hl.dsp.global("quickshell:regionRecord")')
        ]
        self.assertEqual(len(active), 1, "expected one active region-record bind in generated Lua")
