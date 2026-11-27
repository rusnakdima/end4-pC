import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

TILES = {
    "modules/ii/sidebarRight/quickToggles/classicStyle/NetworkToggle.qml": "wifi",
    "modules/ii/sidebarRight/quickToggles/classicStyle/BluetoothToggle.qml": "bluetooth",
    "modules/ii/sidebarRight/quickToggles/androidStyle/AndroidNetworkToggle.qml": "wifi",
    "modules/ii/sidebarRight/quickToggles/androidStyle/AndroidBluetoothToggle.qml": "bluetooth",
}


class SettingsTileRedirectTest(unittest.TestCase):
    def test_tiles_open_the_matching_settings_page(self):
        for path, page in TILES.items():
            with self.subTest(path=path):
                text = (ROOT / path).read_text(encoding="utf-8")
                self.assertIn(
                    f'GlobalStates.settingsTarget = {{ page: "{page}" }}', text
                )
                self.assertIn("GlobalStates.settingsOpen = true", text)

    def test_existing_dialog_forwarding_is_kept(self):
        text = (ROOT / "modules/ii/sidebarRight/SidebarRightContent.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn("onOpenWifiDialog", text)
        self.assertIn("onOpenBluetoothDialog", text)
        self.assertIn("root.showWifiDialog = true", text)
        self.assertIn("root.showBluetoothDialog = true", text)


if __name__ == "__main__":
    unittest.main()
