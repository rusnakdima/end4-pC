import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "hyprland" / "patch-autostart.py"
spec = importlib.util.spec_from_file_location("patch_autostart", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
patch = module.patch


LEGACY = 'hl.exec_cmd("sh -c \'sleep 5; pgrep -x qs >/dev/null || exec qs -p /path/to/config\'")'
WRAPPED = 'hl.exec_cmd("bash -c \'\\"$HOME/.config/quickshell/end4-pC/scripts/bluetooth/wait-for-bluez.sh\\" && exec qs -n -p /path/to/config\'")'
DIRECT = 'hl.exec_cmd("qs -n -p /path/to/config")'


class PatchAutostartTests(unittest.TestCase):
    def test_legacy_line_becomes_direct(self):
        self.assertEqual(patch(LEGACY), (DIRECT, 1))

    def test_wrapped_line_is_unwrapped(self):
        self.assertEqual(patch(WRAPPED), (DIRECT, 1))

    def test_direct_line_is_unchanged(self):
        self.assertEqual(patch(DIRECT), (DIRECT, 0))

    def test_unrelated_lua_is_unchanged(self):
        text = "hl.env(\"X\", \"1\")\n"
        self.assertEqual(patch(text), (text, 0))


if __name__ == "__main__":
    unittest.main()
