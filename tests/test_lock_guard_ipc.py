#!/usr/bin/env python3
"""The lock guard must address the running QuickShell instance by id."""

import importlib.machinery
import importlib.util
import pathlib
import subprocess
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts/lock/end4pc-lock-guard"


def load_guard():
    loader = importlib.machinery.SourceFileLoader("end4pc_lock_guard", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class IpcStatusTest(unittest.TestCase):
    def test_uses_running_instance_id(self):
        guard = load_guard()
        listing = (
            "Instance r23gbhn2pt:\n"
            "  Process ID: 750483\n"
            "  Shell ID: 6501bbd575b961a27df00e30ab48a4fd\n"
            f"  Config path: {guard.CONFIG_PATH}/shell.qml\n"
            "  Display connection: wayland/wayland-2\n"
        )
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append(cmd)
            if cmd[:2] == ["qs", "list"]:
                return subprocess.CompletedProcess(cmd, 0, listing, "")
            return subprocess.CompletedProcess(cmd, 0, "unlocked\n", "")

        with mock.patch.object(guard.subprocess, "run", side_effect=fake_run):
            self.assertEqual(guard.ipc_status(), "unlocked")

        self.assertTrue(
            any("--id" in cmd and "r23gbhn2pt" in cmd for cmd in calls),
            f"expected an instance-id IPC call, got {calls}",
        )


if __name__ == "__main__":
    unittest.main()
