#!/usr/bin/env python3
"""Offline unit tests for the source-location / hidden-combo metadata emitted by
scripts/hyprland/get_keybinds.py.

No config files, Hyprland session or external Python modules required.
Run with:  python3 -m unittest tests.test_get_keybinds_metadata -v
"""

import importlib.util
import os
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKEND = os.path.join(REPO, "scripts", "hyprland", "get_keybinds.py")


def _load_backend():
    # get_keybinds.py parses argv at import time; keep unittest's own args out
    # of argparse by giving it a clean argv while the module loads.
    saved = sys.argv[:]
    try:
        sys.argv = [BACKEND]
        spec = importlib.util.spec_from_file_location("get_keybinds", BACKEND)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.argv = saved
    return module


gk = _load_backend()


# 1-based line numbers are intentionally fixed so the assertions below are
# exact; the parser reports 1-based line/endLine values.
LUA_LINES = [
    "--##! Test Section",  # 1
    'hl.bind("SUPER + A", hl.dsp.exec_cmd("echo a"), {description = "One line bind"})',  # 2
    'hl.bind("SUPER + B", function()',  # 3
    '    hl.dispatch(hl.dsp.window.close())',  # 4
    'end, {description = "Three line bind"})',  # 5
    '--#/# bind = SUPER + C,, -- Placeholder bind',  # 6
    'hl.bind("SUPER + D", hl.dsp.exec_cmd("echo d"), {description = "Hidden bind"}) -- [hidden]',  # 7
    'bindAction("SUPER + E", "myAction", hl.dsp.global("quickshell:myAction"), {description = "Bind action bind"})',  # 8
]


def _all_binds(section):
    out = list(section.get("keybinds", []))
    for child in section.get("children", []):
        out.extend(_all_binds(child))
    return out


def _all_sections(section):
    out = [section]
    for child in section.get("children", []):
        out.extend(_all_sections(child))
    return out


def _all_hidden(section):
    out = []
    for sec in _all_sections(section):
        out.extend(sec.get("hiddenCombos", []))
    return out


def _one(binds, comment):
    matches = [b for b in binds if b.get("comment") == comment]
    if len(matches) != 1:
        raise AssertionError(
            "expected exactly one bind with comment %r, found %d" % (comment, len(matches))
        )
    return matches[0]


class KeybindMetadataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fd, cls.path = tempfile.mkstemp(suffix=".lua")
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(LUA_LINES) + "\n")
        cls.result = gk.parse_keys(cls.path)
        cls.binds = _all_binds(cls.result)

    @classmethod
    def tearDownClass(cls):
        os.unlink(cls.path)

    # -- backward-compatible shape -----------------------------------------
    def test_parser_shape_is_backward_compatible(self):
        for key in ("children", "keybinds", "name"):
            self.assertIn(key, self.result)
        for bind in self.binds:
            for key in ("mods", "key", "dispatcher", "params", "comment", "action"):
                self.assertIn(key, bind)

    # -- metadata present on every emitted bind ----------------------------
    def test_every_bind_has_source_location(self):
        self.assertTrue(self.binds)
        for bind in self.binds:
            self.assertEqual(bind["sourcePath"], self.path)
            self.assertIsInstance(bind["line"], int)
            self.assertIsInstance(bind["endLine"], int)

    def test_every_section_has_hidden_combos(self):
        sections = _all_sections(self.result)
        self.assertTrue(sections)
        for section in sections:
            self.assertIn("hiddenCombos", section)
            self.assertIsInstance(section["hiddenCombos"], list)

    # -- exact line numbers -------------------------------------------------
    def test_one_line_bind_metadata(self):
        bind = _one(self.binds, "One line bind")
        self.assertEqual(bind["line"], 2)
        self.assertEqual(bind["endLine"], 2)

    def test_three_line_bind_metadata(self):
        bind = _one(self.binds, "Three line bind")
        self.assertEqual(bind["line"], 3)
        self.assertEqual(bind["endLine"], 5)
        self.assertEqual(bind["endLine"], bind["line"] + 2)

    def test_placeholder_bind_carries_line_metadata(self):
        bind = _one(self.binds, "Placeholder bind")
        self.assertEqual(bind["sourcePath"], self.path)
        self.assertEqual(bind["line"], 6)
        self.assertEqual(bind["endLine"], 6)

    def test_bind_action_metadata(self):
        bind = _one(self.binds, "Bind action bind")
        self.assertEqual(bind["line"], 8)
        self.assertEqual(bind["endLine"], 8)

    # -- hidden combos ------------------------------------------------------
    def test_hidden_combo_recorded_and_bind_not_emitted(self):
        hidden = _all_hidden(self.result)
        self.assertIn("SUPER + D", hidden)
        # The hidden bind never reaches the emitted keybinds.
        self.assertNotIn(
            "Hidden bind", [b.get("comment") for b in self.binds]
        )
        combos = [" + ".join([*b.get("mods", []), b.get("key", "")]) for b in self.binds]
        self.assertNotIn("SUPER + D", combos)

    def test_root_level_hidden_combo_is_on_root_section(self):
        # A [hidden] bind above the first section marker is recorded on the
        # root Section's hiddenCombos. The QML keybinds aggregate must keep
        # this root-level list, otherwise allUsedCombos misses the combo.
        fd, path = tempfile.mkstemp(suffix=".lua")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(
                    'hl.bind("CTRL + R", hl.dsp.exec_cmd("echo r"), '
                    '{description = "Root hidden"}) -- [hidden]\n'
                    "--##! Section\n"
                    'hl.bind("CTRL + T", hl.dsp.exec_cmd("echo t"), '
                    '{description = "Visible"})\n'
                )
            result = gk.parse_keys(path)
            self.assertEqual(result["hiddenCombos"], ["CTRL + R"])
            self.assertEqual(
                [b.get("comment") for b in _all_binds(result)], ["Visible"]
            )
        finally:
            os.unlink(path)

    # -- launcher block exclusion -------------------------------------------
    def test_launcher_block_inside_section_is_fully_excluded(self):
        # Every bind between the tap-super launcher markers must be invisible
        # to the export: not emitted, not a hidden combo, not rebindable.
        lines = [
            "--##! Apps",  # 1
            'hl.bind("CTRL + A", hl.dsp.exec_cmd("echo a"), {description = "Before bind"})',  # 2
            "-- >>> end4-pC tap-super launcher keybinds (managed by end4-pC)",  # 3
            'hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd("qs launcher"), {description = "Shell: Toggle search"})',  # 4
            'hl.bind("SUPER + SUPER_R", hl.dsp.exec_cmd("qs launcher"), {description = "Hidden launcher"}) -- [hidden]',  # 5
            "--#/# bind = SUPER + X,, -- Placeholder launcher",  # 6
            "-- <<< end4-pC tap-super launcher keybinds",  # 7
            'hl.bind("CTRL + Z", hl.dsp.exec_cmd("echo z"), {description = "After bind"})',  # 8
        ]
        launcher_combos = ("SUPER + SUPER_L", "SUPER + SUPER_R", "SUPER + X")
        fd, path = tempfile.mkstemp(suffix=".lua")
        try:
            with os.fdopen(fd, "w") as f:
                f.write("\n".join(lines) + "\n")
            result = gk.parse_keys(path)
            binds = _all_binds(result)
            self.assertEqual(
                [b.get("comment") for b in binds], ["Before bind", "After bind"]
            )
            emitted = [" + ".join([*b.get("mods", []), b.get("key", "")]) for b in binds]
            hidden = _all_hidden(result)
            for combo in launcher_combos:
                self.assertNotIn(combo, emitted)
                self.assertNotIn(combo, hidden)
            before = _one(binds, "Before bind")
            after = _one(binds, "After bind")
            self.assertEqual(before["sourcePath"], path)
            self.assertEqual((before["line"], before["endLine"]), (2, 2))
            self.assertEqual(after["sourcePath"], path)
            self.assertEqual((after["line"], after["endLine"]), (8, 8))
        finally:
            os.unlink(path)

    def test_launcher_block_at_top_level_is_fully_excluded(self):
        # The same exclusion must hold when the marker block is not nested in
        # a section (as in the real custom/keybinds.lua).
        lines = [
            'hl.bind("CTRL + A", hl.dsp.exec_cmd("echo a"), {description = "Before bind"})',  # 1
            "-- >>> end4-pC tap-super launcher keybinds (managed by end4-pC)",  # 2
            'hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd("qs launcher"), {description = "Shell: Toggle search"})',  # 3
            "--#/# bind = SUPER + X,, -- Placeholder launcher",  # 4
            "-- <<< end4-pC tap-super launcher keybinds",  # 5
            'hl.bind("CTRL + Z", hl.dsp.exec_cmd("echo z"), {description = "After bind"})',  # 6
        ]
        fd, path = tempfile.mkstemp(suffix=".lua")
        try:
            with os.fdopen(fd, "w") as f:
                f.write("\n".join(lines) + "\n")
            result = gk.parse_keys(path)
            binds = _all_binds(result)
            self.assertEqual(
                [b.get("comment") for b in binds], ["Before bind", "After bind"]
            )
            hidden = _all_hidden(result)
            for combo in ("SUPER + SUPER_L", "SUPER + X"):
                self.assertNotIn(combo, hidden)
            self.assertEqual(_one(binds, "Before bind")["line"], 1)
            self.assertEqual(_one(binds, "After bind")["line"], 6)
            self.assertEqual(_one(binds, "After bind")["endLine"], 6)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
