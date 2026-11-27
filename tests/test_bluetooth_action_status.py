"""The Bluetooth helper must report action failures separately from state JSON."""

import importlib.util
import io
import json
import pathlib
import unittest
from unittest import mock

HELPER = (
    pathlib.Path(__file__).resolve().parents[1]
    / "scripts"
    / "bluetooth"
    / "bluez-state.py"
)
SPEC = importlib.util.spec_from_file_location("bluez_state", HELPER)
bluez_state = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bluez_state)


class Completed:
    def __init__(self, stdout="", stderr="", returncode=0):
        self.stdout = stdout
        self.stderr = stderr
        self.returncode = returncode


def run_helper(result, argv):
    output = io.StringIO()
    with mock.patch.object(bluez_state.subprocess, "run", return_value=result), \
         mock.patch.object(bluez_state, "query", return_value={"available": True}), \
         mock.patch("sys.stdout", output), \
         mock.patch("sys.argv", ["bluez-state.py", *argv]):
        bluez_state.main()
    return json.loads(output.getvalue())


class BluetoothActionStatusTest(unittest.TestCase):
    def test_successful_action_reports_no_error(self):
        payload = run_helper(Completed(stdout="Changing power on succeeded\n"),
                             ["--power", "on"])
        self.assertEqual(payload["lastActionError"], "")

    def test_bluetoothctl_failure_text_is_reported(self):
        payload = run_helper(
            Completed(stdout="Device 00:11:22:33:44:55 not available\n"),
            ["--pair", "00:11:22:33:44:55"],
        )
        self.assertIn("not available", payload["lastActionError"])

    def test_nonzero_exit_and_stderr_are_reported(self):
        payload = run_helper(
            Completed(stdout="", stderr="Failed to connect: No such device\n", returncode=1),
            ["--connect", "00:11:22:33:44:55"],
        )
        self.assertIn("Failed to connect", payload["lastActionError"])


if __name__ == "__main__":
    unittest.main()
