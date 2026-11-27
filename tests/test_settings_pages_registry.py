"""Wi-Fi and Bluetooth must be reachable as normal Settings pages."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "services/SettingsPages.qml"
SEARCH_INDEX = ROOT / "services/SettingsSearchIndex.qml"
PAGES = ROOT / "modules/ii/settings/pages"
DOCS = ROOT / "docs/settings-pages.md"


class SettingsPagesRegistryTest(unittest.TestCase):
    def setUp(self):
        self.source = REGISTRY.read_text()

    def test_wifi_and_bluetooth_pages_are_registered(self):
        for page_id in ("wifi", "bluetooth"):
            self.assertIn('id: "%s"' % page_id, self.source)

    def test_page_files_exist(self):
        for name in ("WifiConfig.qml", "BluetoothConfig.qml"):
            self.assertTrue((PAGES / name).is_file(), name)

    def test_search_index_has_wifi_and_bluetooth_keywords(self):
        text = SEARCH_INDEX.read_text()
        self.assertIn('wifi: ["network", "wireless", "wifi"]', text)
        self.assertIn('bluetooth: ["bluetooth", "pair"]', text)

    def test_settings_docs_describe_pages_and_tile_redirect(self):
        self.assertTrue(DOCS.is_file(), "docs/settings-pages.md")
        text = DOCS.read_text()
        self.assertIn("Wi-Fi", text)
        self.assertIn("Bluetooth", text)
        self.assertIn("settingsTarget", text)
