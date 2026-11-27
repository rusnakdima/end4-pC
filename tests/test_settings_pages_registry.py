"""Wi-Fi and Bluetooth must be reachable as normal Settings pages."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "services/SettingsPages.qml"
PAGES = ROOT / "modules/ii/settings/pages"


class SettingsPagesRegistryTest(unittest.TestCase):
    def setUp(self):
        self.source = REGISTRY.read_text()

    def test_wifi_and_bluetooth_pages_are_registered(self):
        for page_id in ("wifi", "bluetooth"):
            self.assertIn('id: "%s"' % page_id, self.source)

    def test_page_files_exist(self):
        for name in ("WifiConfig.qml", "BluetoothConfig.qml"):
            self.assertTrue((PAGES / name).is_file(), name)
