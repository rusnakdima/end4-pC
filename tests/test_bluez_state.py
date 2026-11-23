"""Offline tests for scripts/bluetooth/bluez-state.py.

A fake bluetoothctl on PATH supplies canned BlueZ output, so these tests need
no adapter, daemon or D-Bus session. Run via tests/run-python-tests.sh.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HELPER = REPO / "scripts" / "bluetooth" / "bluez-state.py"

STUB = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BT_STUB_LOG"
case "$*" in
  "--timeout 1 show")
    printf '%b\n' \
      'Controller 90:DE:80:29:0C:64 (public)' \
      '\tPowered: yes' \
      '\tDiscovering: no'
    ;;
  "--timeout 1 devices")
    printf '%s\n' \
      'Device 70:A4:B5:D6:03:E0 OneOdio A70' \
      'Device 11:22:33:44:55:66 Phone'
    ;;
  "--timeout 1 info 70:A4:B5:D6:03:E0")
    printf '%b\n' \
      'Device 70:A4:B5:D6:03:E0 (public)' \
      '\tAlias: OneOdio A70' \
      '\tIcon: audio-headset' \
      '\tPaired: yes' \
      '\tConnected: yes' \
      '\tBattery Percentage: 0x4b (75)'
    ;;
  "--timeout 1 info 11:22:33:44:55:66")
    printf '%b\n' \
      'Device 11:22:33:44:55:66 (public)' \
      '\tAlias: Phone' \
      '\tIcon: phone' \
      '\tPaired: yes' \
      '\tConnected: no'
    ;;
  *) ;;
esac
exit 0
"""


class BluetoothStateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        bindir = Path(self.tmp.name)
        stub = bindir / "bluetoothctl"
        stub.write_text(STUB, encoding="utf-8")
        stub.chmod(0o755)
        self.log = bindir / "calls.log"
        self.log.touch()
        self.env = dict(os.environ)
        self.env["PATH"] = str(bindir) + os.pathsep + self.env.get("PATH", "")
        self.env["BT_STUB_LOG"] = str(self.log)

    def run_helper(self, *args):
        proc = subprocess.run(
            [sys.executable, "-I", str(HELPER), *args],
            capture_output=True,
            text=True,
            env=self.env,
            timeout=10,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(proc.stdout.strip().splitlines()[-1])

    def calls(self):
        return [line.split() for line in self.log.read_text().splitlines() if line]

    def test_query_reports_adapter_and_devices(self):
        state = self.run_helper()
        self.assertTrue(state["available"])
        self.assertTrue(state["enabled"])
        self.assertFalse(state["discovering"])
        by_addr = {d["address"]: d for d in state["devices"]}
        self.assertEqual(set(by_addr), {"70:A4:B5:D6:03:E0", "11:22:33:44:55:66"})
        headset = by_addr["70:A4:B5:D6:03:E0"]
        self.assertEqual(headset["name"], "OneOdio A70")
        self.assertEqual(headset["icon"], "audio-headset")
        self.assertTrue(headset["paired"])
        self.assertTrue(headset["connected"])
        self.assertTrue(headset["batteryAvailable"])
        self.assertAlmostEqual(headset["battery"], 0.75)
        self.assertFalse(by_addr["11:22:33:44:55:66"]["connected"])
        self.assertFalse(by_addr["11:22:33:44:55:66"]["batteryAvailable"])

    def test_query_without_controller_is_unavailable(self):
        log = self.log.read_text()
        # Replace the stub so `show` reports no controller.
        stub_source = STUB.replace(
            "'Controller 90:DE:80:29:0C:64 (public)' \\\n      '\\tPowered: yes' \\\n      '\\tDiscovering: no'",
            "'No default controller available'",
        )
        (Path(self.tmp.name) / "bluetoothctl").write_text(
            stub_source, encoding="utf-8"
        )
        (Path(self.tmp.name) / "bluetoothctl").chmod(0o755)
        state = self.run_helper()
        self.assertFalse(state["available"])
        self.assertFalse(state["enabled"])
        self.assertEqual(state["devices"], [])

    def test_actions_run_commands_and_reemit_state(self):
        state = self.run_helper("--power", "on", "--connect", "AA:BB")
        self.assertTrue(state["available"])
        self.assertIn(["--timeout", "1", "power", "on"], self.calls())
        self.assertIn(["--timeout", "1", "connect", "AA:BB"], self.calls())


class BluetoothStateTimingTest(unittest.TestCase):
    """The query must not pay the bluetoothctl --timeout cost once per device."""

    SLOW_STUB = r"""#!/usr/bin/env bash
sleep 0.4
case "$*" in
  "--timeout 1 show")
    printf '%b\n' 'Controller 90:DE:80:29:0C:64 (public)' '\tPowered: yes'
    ;;
  "--timeout 1 devices")
    printf '%s\n' \
      'Device 70:A4:B5:D6:03:E0 OneOdio A70' \
      'Device 11:22:33:44:55:66 Phone' \
      'Device 41:42:FF:69:A2:92 Speaker'
    ;;
  "--timeout 1 info "*) printf '%s\n' 'Paired: yes' ;;
esac
"""

    def test_query_runs_bluetoothctl_calls_concurrently(self):
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp)
            stub = bindir / "bluetoothctl"
            stub.write_text(self.SLOW_STUB, encoding="utf-8")
            stub.chmod(0o755)
            env = dict(os.environ)
            env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
            start = time.monotonic()
            proc = subprocess.run(
                [sys.executable, "-I", str(HELPER)],
                capture_output=True,
                text=True,
                env=env,
                timeout=10,
            )
            elapsed = time.monotonic() - start
            self.assertEqual(proc.returncode, 0, proc.stderr)
            state = json.loads(proc.stdout.strip())
            self.assertEqual(len(state["devices"]), 3)
            # 5 calls x 0.4 s = 2.0 s if run sequentially; concurrency keeps
            # the whole query close to a single call's latency.
            self.assertLess(elapsed, 1.2, f"query took {elapsed:.2f}s")


if __name__ == "__main__":
    unittest.main()
