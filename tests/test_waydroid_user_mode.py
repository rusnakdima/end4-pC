#!/usr/bin/env python3
"""Offline contract tests for the user-mode Waydroid scripts.

The theme used to shell out to `waydroid shell pm ...` (root-only) and start
sessions with a bare `waydroid session start &`. These tests pin the
user-mode behaviour with stubbed commands, so a theme sync cannot silently
reintroduce the root-only scripts.
"""

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPTS = REPO / "scripts"

STATUS = "Session:\tRUNNING\nContainer:\tRUNNING\nVendor type:\tMAINLINE\n"
APP_LIST = "\n".join([
    "Name: Firefox",
    "packageName: org.mozilla.firefox",
    "",
    "Name: F-Droid",
    "packageName: org.fdroid.fdroid",
]) + "\n"

WAYDROID_STUB = """#!/bin/bash
printf '%s %s\\n' "$(basename "$0")" "$*" >> "$CALL_LOG"
if [[ "$1" == "status" ]]; then printf '%b' "$STUB_STATUS"; exit 0; fi
if [[ "$1" == "app" && "$2" == "list" ]]; then printf '%b' "$STUB_APP_LIST"; exit 0; fi
if [[ "$1" == "shell" ]]; then echo "ROOT ONLY CALLED" >&2; fi
exit 0
"""

CALL_LOG_STUB = """#!/bin/bash
printf '%s %s\\n' "$(basename "$0")" "$*" >> "$CALL_LOG"
exit 0
"""


class WaydroidUserModeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.call_log = self.root / "calls.log"

        for name, body in (("waydroid", WAYDROID_STUB),
                           ("update-desktop-database", CALL_LOG_STUB),
                           ("waydroid-user-start", CALL_LOG_STUB)):
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)

        self.env = dict(os.environ)
        self.env.update({
            "HOME": str(self.root),
            "PATH": f"{self.bin}:{self.env['PATH']}",
            "CALL_LOG": str(self.call_log),
            "STUB_STATUS": STATUS.replace("\n", "\\n"),
            "STUB_APP_LIST": APP_LIST.replace("\n", "\\n"),
        })

    def calls(self):
        if not self.call_log.exists():
            return []
        return self.call_log.read_text().splitlines()

    def test_desktop_gen_uses_app_list_and_not_root_shell(self):
        script = SCRIPTS / "waydroid-desktop-gen.sh"
        proc = subprocess.run([str(script), str(self.root / "apps")],
                              env=self.env, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse(any("shell" in line for line in self.calls()),
                         "desktop generator called root-only 'waydroid shell'")
        desktop = self.root / "apps" / "waydroid.org.mozilla.firefox.desktop"
        self.assertTrue(desktop.exists(), "no desktop file for Firefox")
        text = desktop.read_text()
        self.assertIn("Exec=", text)
        self.assertIn("waydroid-app-launcher.sh org.mozilla.firefox", text)

    def test_app_launcher_starts_session_then_launches_app(self):
        script = SCRIPTS / "waydroid-app-launcher.sh"
        proc = subprocess.run([str(script), "org.mozilla.firefox"],
                              env=self.env, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        calls = self.calls()
        self.assertTrue(any(c.startswith("waydroid-user-start") for c in calls),
                        "launcher did not ensure the user session")
        self.assertTrue(any(c.startswith("waydroid app launch org.mozilla.firefox") for c in calls))
        self.assertFalse(any("shell" in c for c in calls))

    def test_installer_sets_up_user_privileges_and_uses_helper(self):
        installer = REPO / "optional" / "waydroid" / "install-waydroid.sh"
        text = installer.read_text()
        self.assertIn("setup_user_privileges()", text)
        self.assertIn("/etc/sudoers.d/zz-waydroid", text)
        self.assertIn("waydroid-user-start", text)
        self.assertIn("setup_user_privileges", text.split("main() {")[1])

    def test_user_start_helper_is_user_only_and_checks_container(self):
        script = SCRIPTS / "waydroid-user-start"
        self.assertTrue(script.exists(), "waydroid-user-start helper missing from repo scripts")
        text = script.read_text()
        self.assertTrue(os.access(script, os.X_OK))
        self.assertIsNone(re.search(r"^\s*sudo\b", text, re.MULTILINE),
                          "helper invokes sudo directly")
        self.assertIn("Container:.*RUNNING", text)

    def test_shell_actions_are_bounded_so_a_hung_start_cannot_lock_the_ui(self):
        service = (REPO / "services/Waydroid.qml").read_text()
        # `start()` must not be able to hang forever - the guest can leave
        # D-Bus calls waiting, and a stuck action would keep `busy` true and
        # block every other control in the panel.
        self.assertRegex(service, r'actionProc\.command\s*=\s*\["timeout"',
                         "start action is not bounded by timeout")
        self.assertRegex(service, r'command:\s*\["timeout",\s*"[^"]+",\s*"waydroid",\s*"show-full-ui"\]',
                         "open-full-ui action is not bounded by timeout")

    def test_shell_ui_wires_waydroid_quick_toggle(self):
        panel = REPO / "modules/ii/sidebarRight/quickToggles/AndroidQuickPanel.qml"
        self.assertIn('"waydroid"', panel.read_text(),
                      "waydroid missing from available quick toggle types")

        chooser = REPO / "modules/ii/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
        chooser_text = chooser.read_text()
        self.assertIn('roleValue: "waydroid"', chooser_text)
        self.assertIn("AndroidWaydroidToggle", chooser_text)

        model = REPO / "modules/common/models/quickToggles/WaydroidToggle.qml"
        self.assertTrue(model.exists(), "WaydroidToggle model missing")
        model_text = model.read_text()
        self.assertIn("QuickToggleModel", model_text)
        self.assertIn("Waydroid.statusText", model_text)

        android_button = REPO / "modules/ii/sidebarRight/quickToggles/androidStyle/AndroidWaydroidToggle.qml"
        self.assertTrue(android_button.exists(), "AndroidWaydroidToggle missing")
        self.assertIn("toggleModel: WaydroidToggle", android_button.read_text())

        config = (REPO / "modules/common/Config.qml").read_text()
        self.assertIn('"type": "waydroid"', config,
                      "no default waydroid quick toggle slot")


if __name__ == "__main__":
    unittest.main()
