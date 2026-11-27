"""The new categorized style is offered everywhere the style is chosen."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SettingsStyleOptionTest(unittest.TestCase):
    def test_config_documents_categories_style(self):
        text = (ROOT / "modules/common/Config.qml").read_text()
        self.assertIn(
            'property string style: "default" // default - minimal - dashboard - categories',
            text,
        )

    def test_quick_controls_offers_categories(self):
        text = (ROOT / "services/SettingsQuickControls.qml").read_text()
        self.assertIn('value: "categories"', text)

    def test_dashboard_style_card_is_searchable(self):
        text = (ROOT / "modules/ii/settings/DashboardSettingsPage.qml").read_text()
        self.assertIn("settings panel style default minimal dashboard categories", text)

    def test_one_loader_switches_between_the_two_content_components(self):
        # A single Loader with a style-driven source means toggling styles at
        # runtime can never leave a stale content component active.
        text = (ROOT / "modules/ii/settings/Settings.qml").read_text()
        self.assertNotIn("sourceComponent: SettingsContent", text)
        self.assertIn('Config.options.settings.style === "categories"', text)
        self.assertIn('"CategoriesSettingsContent.qml"', text)
        self.assertIn('"SettingsContent.qml"', text)


if __name__ == "__main__":
    unittest.main()
