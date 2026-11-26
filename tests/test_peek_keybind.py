#!/usr/bin/env python3
"""Offline checks for the Peek keybind catalog entries and window rules.

Run with: python3 -m unittest tests.test_peek_keybind -v
"""

import json
import os
import re
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "defaults", "hyprland", "keybinds.json")
SNIPPET = os.path.join(REPO, "defaults", "hyprland", "keybinds-snippet.lua")


def peek_target(entry):
    dispatch = entry.get("dispatch", {})
    arg = dispatch.get("arg", {})
    return dispatch.get("kind") == "global" and arg.get("value") == "quickshell:peek"


class PeekKeybindTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(CATALOG, encoding="utf-8") as fh:
            cls.catalog = json.load(fh)

    def test_alt_space_binds_peek(self):
        matches = [
            entry
            for entry in self.catalog["binds"]
            if entry.get("combo") == "ALT + SPACE" and peek_target(entry)
        ]
        self.assertEqual(len(matches), 1)
        self.assertRegex(matches[0]["id"], r"^utilities-\d+$")
        self.assertEqual(matches[0]["description"], "Utilities: Peek preview")

    def test_super_shift_space_fallback_binds_peek(self):
        matches = [
            entry
            for entry in self.catalog["binds"]
            if entry.get("combo") == "SUPER + SHIFT + SPACE" and peek_target(entry)
        ]
        self.assertEqual(len(matches), 1)

    def test_space_alone_is_never_bound(self):
        combos = [entry.get("combo") for entry in self.catalog["binds"]]
        self.assertNotIn("SPACE", combos)
        for entry in self.catalog["binds"]:
            if peek_target(entry):
                self.assertNotEqual(entry.get("combo"), "SPACE")
        for combo in ("SUPER + SPACE", "SUPER + ALT + SPACE"):
            self.assertNotIn(combo, combos)

    def test_preamble_declares_peek_window_rules(self):
        preamble = "".join(self.catalog["preamble"]) + "".join(self.catalog["customPreamble"])
        self.assertIn("end4-pc peek window rules", preamble.lower())
        self.assertIn('title = "Peek"', preamble)
        self.assertIn("end4-pc-peek", preamble)
        self.assertIn("monitor_w * 0.75", preamble)

    def test_snippet_declares_binds_and_window_rules(self):
        with open(SNIPPET, encoding="utf-8") as fh:
            snippet = fh.read()
        self.assertIn('hl.bind("ALT + SPACE"', snippet)
        self.assertIn('hl.bind("SUPER + SHIFT + SPACE"', snippet)
        self.assertIn('title = "Peek"', snippet)
        self.assertIn("end4-pc-peek", snippet)
        self.assertIn("monitor_w * 0.75", snippet)
        self.assertIn("end4-pc peek window rules", snippet.lower())


if __name__ == "__main__":
    unittest.main()
