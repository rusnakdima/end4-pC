import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "defaults/hyprland/keybinds.json"


class ReloadBindCommandTest(unittest.TestCase):
    def test_catalog_reload_bind_uses_live_ipc_and_no_duplicate_fallback(self):
        catalog = json.loads(CATALOG.read_text())
        bind = next(b for b in catalog["binds"] if b["id"] == "bind-26")
        self.assertEqual(bind["combo"], "CTRL + SUPER + R")
        self.assertIn('"env WAYLAND_DISPLAY=wayland-1 " .. qsIpcCall .. " wallpapers reloadShell', bind["code"])
        self.assertIn("qs -n -p $HOME/.config/quickshell/$qsConfig", bind["code"])
        self.assertNotIn("|| qs -p", bind["code"])

    def test_generated_lua_reload_bind_matches_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / "main.lua"
            custom = Path(tmp) / "custom.lua"
            subprocess.run([
                "python3", str(ROOT / "scripts/hyprland/generate_keybinds.py"),
                "--catalog", str(CATALOG),
                "--main-out", str(main), "--custom-out", str(custom),
            ], check=True, capture_output=True, text=True)
            lua = (main.read_text() + custom.read_text()).splitlines()
        reload_lines = [line for line in lua if line.startswith('hl.bind("CTRL + SUPER + R"')]
        self.assertEqual(len(reload_lines), 1)
        self.assertIn("WAYLAND_DISPLAY=wayland-1", reload_lines[0])
        self.assertIn("qs -n -p", reload_lines[0])
