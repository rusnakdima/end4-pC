import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "desktop": ROOT / "modules/ii/desktopMenu/DesktopMenu.qml",
    "overlay": ROOT / "modules/ii/overlay/StyledOverlayWidget.qml",
    "osd_ii": ROOT / "modules/ii/onScreenDisplay/OnScreenDisplay.qml",
    "osd_waffle": ROOT / "modules/waffle/onScreenDisplay/WaffleOSD.qml",
    "action": ROOT / "modules/waffle/actionCenter/WaffleActionCenter.qml",
    "notifications": ROOT / "modules/waffle/notificationCenter/WaffleNotificationCenter.qml",
    "start": ROOT / "modules/waffle/startMenu/StartMenuContent.qml",
    "settings": ROOT / "modules/ii/settings/Settings.qml",
}


def escape_branch(path):
    text = path.read_text()
    pos = text.find("Qt.Key_Escape")
    return "" if pos == -1 else text[pos:pos + 400]


def keys_depths_relative_to_window(path):
    """Brace depth of every Keys.onPressed relative to the PanelWindow."""
    depth = 0
    window_depth = None
    depths = []
    for line in path.read_text().splitlines():
        code = line.split("//")[0]
        if window_depth is None and "PanelWindow {" in code:
            window_depth = depth
        if "Keys.onPressed" in code:
            depths.append(depth - window_depth)
        depth += code.count("{") - code.count("}")
    return depths


class EscapeWiringTest(unittest.TestCase):
    def test_desktop_menu_escape_closes(self):
        self.assertIn("Qt.Key_Escape", escape_branch(FILES["desktop"]))
        self.assertIn("openCentered(false)", escape_branch(FILES["desktop"]))

    def test_overlay_widget_escape_closes(self):
        self.assertIn("Qt.Key_Escape", escape_branch(FILES["overlay"]))
        self.assertIn("root.close()", escape_branch(FILES["overlay"]))

    def test_osd_escape_closes_both_families(self):
        for key in ("osd_ii", "osd_waffle"):
            with self.subTest(key=key):
                self.assertIn("Qt.Key_Escape", escape_branch(FILES[key]))
                self.assertIn("= false", escape_branch(FILES[key]))

    def test_sidebar_escape_closes_via_onClosed(self):
        for key in ("action", "notifications"):
            with self.subTest(key=key):
                self.assertIn("Qt.Key_Escape", escape_branch(FILES[key]))
                self.assertIn("content.close()", escape_branch(FILES[key]))

    def test_start_menu_escape_closes_instead_of_returning(self):
        branch = escape_branch(FILES["start"])
        self.assertIn("GlobalStates.searchOpen = false", branch)
        self.assertNotIn("\n            return;", branch)

    def test_escape_keys_are_attached_to_items_not_windows(self):
        for key in ("desktop", "osd_ii", "osd_waffle", "action", "notifications"):
            with self.subTest(key=key):
                depths = keys_depths_relative_to_window(FILES[key])
                self.assertTrue(depths, "expected a Keys.onPressed handler")
                self.assertTrue(all(d > 1 for d in depths),
                                f"Keys.onPressed must be on a child Item, got depths {depths}")

    def test_sidebar_base_escape_closes_itself(self):
        text = (ROOT / "modules/waffle/looks/WBarAttachedPanelContent.qml").read_text()
        self.assertIn("root.close()", text)
        self.assertNotIn("content.close()", text)

    def test_settings_escape_still_cancel_first(self):
        helper = (ROOT / "modules/common/functions/SettingsEscape.js").read_text()
        self.assertIn("cancel", helper.lower())
        diff = subprocess.run(
            ["git", "diff", "--quiet", "HEAD", "--", str(FILES["settings"])],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(diff.returncode, 0, "Settings.qml must stay unchanged")
