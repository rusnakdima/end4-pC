"""Every Settings page belongs to one of the five category groups."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "services/SettingsPages.qml"

ALLOWED = {
    "Network & internet",
    "Connected devices",
    "Personalization",
    "System",
    "About",
}

EXPECTED = {
    "wifi": "Network & internet",
    "bluetooth": "Connected devices",
    "default-apps": "System",
    "keyboard": "System",
    "about": "About",
}


class SettingsCategoriesTest(unittest.TestCase):
    def setUp(self):
        self.text = SOURCE.read_text(encoding="utf-8")

    def test_every_page_has_an_allowed_category(self):
        entries = re.findall(r'\{\s*id:\s*"([^"]+)"[^}]*\}', self.text)
        self.assertGreater(len(entries), 10)
        for line in self.text.splitlines():
            if not re.search(r'\{\s*id:\s*"[^"]+"', line):
                continue
            match = re.search(r'category:\s*"([^"]+)"', line)
            self.assertIsNotNone(match, line)
            self.assertIn(match.group(1), ALLOWED, line)

    def test_category_helpers_are_declared(self):
        self.assertIn("property var categories", self.text)
        self.assertIn("function pagesInCategory", self.text)
        self.assertIn('?? "System"', self.text)

    def test_key_pages_are_in_the_expected_categories(self):
        for page_id, category in EXPECTED.items():
            with self.subTest(page=page_id):
                line = next(
                    l for l in self.text.splitlines()
                    if re.search(r'\{\s*id:\s*"%s"' % re.escape(page_id), l)
                )
                self.assertIn('category: "%s"' % category, line)


if __name__ == "__main__":
    unittest.main()
