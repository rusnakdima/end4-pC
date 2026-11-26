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
        self.assertEqual(bind["dispatch"], {
            "kind": "global",
            "arg": {"kind": "string", "value": "quickshell:shellReload"},
        })
        self.assertNotIn("command", bind)
        self.assertEqual(
            bind["code"],
            'hl.bind("CTRL + SUPER + R", hl.dsp.global("quickshell:shellReload"), '
            '{ description = "Shell: Reload theme" })',
        )

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
                self.assertIn("shellReload", main_file.read())


if __name__ == "__main__":
    unittest.main()
