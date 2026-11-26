import unittest
from pathlib import Path

SERVICE = Path(__file__).resolve().parents[1] / "services/GeneratedCommandShortcuts.qml"


def block_after(text, marker):
    start = text.index(marker)
    end = text.find("\n        }", start)
    return text[start:end if end != -1 else len(text)]


class HoldRepeatWiringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SERVICE.read_text()

    def test_repeatable_ids_are_only_the_four_xf86_brightness_volume_bridges(self):
        self.assertIn("repeatableIds", self.text)
        for cid in ("bind-19", "bind-20", "bind-21", "bind-22"):
            self.assertIn('"' + cid + '"', self.text)
        self.assertNotIn('"media-8"', self.text.split("repeatableIds", 1)[1].split("]", 1)[0])

    def test_repeat_stops_on_pressed_false_and_released(self):
        self.assertIn("onPressedChanged", self.text)
        self.assertIn("onReleased", self.text)
        self.assertIn("repeat: true", self.text)
        self.assertIn("stop()", block_after(self.text, "onPressedChanged"))
        self.assertIn("stop()", block_after(self.text, "onReleased"))

    def test_repeat_runs_through_run_command_allowlist(self):
        self.assertIn("runCommand(root.heldRepeatId)", self.text)
        self.assertEqual(self.text.count("Quickshell.execDetached"), 1)
