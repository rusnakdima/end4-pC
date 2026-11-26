import json
import os
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "defaults/hyprland/keybinds.json")
GENERATOR = os.path.join(REPO, "scripts/hyprland/generate_keybinds.py")


class KeybindReloadTest(unittest.TestCase):
    def test_bind_26_dispatches_shell_reload(self):
        with open(CATALOG) as catalog_file:
            binds = json.load(catalog_file)["binds"]
        bind = next(b for b in binds if b["id"] == "bind-26")
        self.assertEqual(bind["combo"], "CTRL + SUPER + R")
        self.assertEqual(bind["description"], "Shell: Reload theme")
        self.assertEqual(bind["label"], "Shell: Reload theme")
        # The bind must live in Hyprland, not in a shortcut Quickshell registers
        # for itself: a shell that is not running has no global shortcuts at all.
        # Hyprland 0.57.2 treats a bare hl.dsp.exec_cmd() bind as a no-op, so
        # the dispatch must be made from a function with hl.dispatch().
        expected = (
            'hl.bind("CTRL + SUPER + R", function() '
            'hl.dispatch(hl.dsp.exec_cmd("env WAYLAND_DISPLAY=wayland-1 " .. '
            'qsIpcCall .. " wallpapers reloadShell || '
            'qs -n -p $HOME/.config/quickshell/$qsConfig")) '
            'end, { description = "Shell: Reload theme" })'
        )
        self.assertEqual(bind["dispatch"]["kind"], "raw")
        self.assertEqual(bind["dispatch"].get("code"), expected)
        self.assertNotIn("command", bind)
        self.assertEqual(bind["code"], expected)
        self.assertNotIn("shellReload", bind["code"])

    def test_generator_omits_bind_26_command(self):
        with tempfile.TemporaryDirectory() as d:
            commands = os.path.join(d, "commands.json")
            subprocess.run(
                [sys.executable, GENERATOR, "--catalog", CATALOG,
                 "--main-out", os.path.join(d, "main.lua"),
                 "--custom-out", os.path.join(d, "custom.lua"),
                 "--commands-out", commands],
                check=True, capture_output=True,
            )
            with open(commands) as commands_file:
                self.assertNotIn("bind-26", json.load(commands_file))
            with open(os.path.join(d, "main.lua")) as main_file:
                main = main_file.read()
            self.assertIn("wallpapers reloadShell", main)
            self.assertIn("WAYLAND_DISPLAY=wayland-1", main)
            self.assertIn("qs -n -p $HOME/.config/quickshell/$qsConfig", main)
            self.assertIn("function() hl.dispatch(hl.dsp.exec_cmd(", main)
            self.assertNotIn('hl.dsp.global("quickshell:shellReload")', main)


if __name__ == "__main__":
    unittest.main()
