"""The default app role catalog must be a readable/editable JSON file."""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "defaults/default-apps.json"

EXPECTED = {
    "terminal": ["apps", "apps-2", "apps-3"],
    "filemanager": ["apps-4"],
    "browser": ["apps-5"],
    "codeeditor": ["apps-6"],
    "office": ["apps-7"],
    "texteditor": ["apps-8"],
    "volumemixer": ["apps-9"],
    "taskmanager": ["apps-11"],
}


class DefaultAppsCatalogTest(unittest.TestCase):
    def test_catalog_contains_every_default_role_with_its_bind_ids(self):
        self.assertTrue(CATALOG.is_file(), f"missing {CATALOG}")
        data = json.loads(CATALOG.read_text())
        roles = data["roles"]
        self.assertEqual([role["id"] for role in roles], list(EXPECTED))
        for role in roles:
            self.assertEqual(role["bindIds"], EXPECTED[role["id"]])
            for field in ("label", "icon", "categories", "hints"):
                self.assertTrue(role[field], f"{role['id']} has empty {field}")

    def test_js_fallback_roles_match_the_json_catalog(self):
        js = (ROOT / "modules/common/functions/DefaultAppsStore.js").read_text()
        for role in json.loads(CATALOG.read_text())["roles"]:
            self.assertIn(f'id: "{role["id"]}"', js)
            self.assertIn('bindIds: [' + ", ".join(f'"{b}"' for b in role["bindIds"]) + ']', js)
