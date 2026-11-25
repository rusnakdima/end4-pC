#!/usr/bin/env python3
"""Behavioural tests for the theme-only lock-screen watchdog.

Runs the real end4pc-lock-guard against PATH shims and a temporary runtime
directory. No live Hyprland, Quickshell or hyprlock is involved.

Every test names the break it catches:

* crash_while_locked_clears_hyprland_crash_screen — without clear_crashed_lockscreen()
  the compositor keeps painting its "lockscreen app died" screen after the
  theme lock has been re-acquired.
* failed_restart_never_falls_back_to_hyprlock — the old code spawned hyprlock,
  which is a second lock client and the exact failure mode being removed.
* failed_restart_is_retried_after_cooldown — without a retry the session stays
  stuck on the crash screen forever after one bad restart.
* unlocked_session_is_left_alone — a stray restart would re-lock the desktop.
* already_secure_lock_is_left_alone — needless restarts recreate the crash.
* legacy_bridge_markers_are_ignored — old markers must not revive hyprlock.
"""

import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUARD = ROOT / "scripts" / "lock" / "end4pc-lock-guard"
SIGNATURE = "TESTSIGNATURE"


SHIMS = {
    "qs": r"""#!/bin/sh
if [ "$3" = "ipc" ]; then
    cat "$MOCK_STATUS_FILE" 2>/dev/null || echo unlocked
    exit 0
fi
echo "qs $*" >> "$MOCK_SHELL_LOG"
exit 0
""",
    "pgrep": r"""#!/bin/sh
if [ "$1" = "-x" ] && [ "$2" = "hyprlock" ]; then
    exit 1
fi
if [ -s "$MOCK_QS_PID_FILE" ]; then
    cat "$MOCK_QS_PID_FILE"
    exit 0
fi
# Emulate `pgrep -f PATTERN` against recorded /proc cmdlines. This is how the
# live shell is found: it is launched with `-n -p <config path>`, not `-c`.
if [ "$1" = "-f" ] && [ -s "$MOCK_QS_CMDLINE_FILE" ]; then
    if grep -E "$2" "$MOCK_QS_CMDLINE_FILE" >/dev/null 2>&1; then
        echo 4242
        exit 0
    fi
fi
exit 1
""",
    "systemctl": r"""#!/bin/sh
echo "systemctl $*" >> "$MOCK_SHELL_LOG"
exit 0
""",
    "systemd-run": r"""#!/bin/sh
echo "systemd-run $*" >> "$MOCK_SHELL_LOG"
if [ "${MOCK_FAIL_SECURE:-0}" = "1" ]; then
    echo "locked-insecure" > "$MOCK_STATUS_FILE"
else
    echo "locked-secure" > "$MOCK_STATUS_FILE"
    echo "4242" > "$MOCK_QS_PID_FILE"
fi
exit 0
""",
    "hyprctl": r"""#!/bin/sh
echo "hyprctl $*" >> "$MOCK_HYPRCTL_LOG"
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" >> "$MOCK_HYPRCTL_LOG"
exit 0
""",
    "hyprlock": r"""#!/bin/sh
echo "hyprlock $*" >> "$MOCK_HYPRLOCK_LOG"
exit 0
""",
}


class GuardHarness:
    def __init__(self, tmp: Path, fail_secure: bool = False):
        self.tmp = tmp
        self.rt = tmp / "rt"
        self.bin = tmp / "bin"
        tmp.mkdir(parents=True, exist_ok=True)
        self.rt.mkdir()
        self.bin.mkdir()
        (self.rt / "hypr" / SIGNATURE).mkdir(parents=True)

        for name, body in SHIMS.items():
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)

        self.status = tmp / "status"
        self.qs_pids = tmp / "qs-pids"
        self.qs_cmdlines = tmp / "qs-cmdlines"
        self.shell_log = tmp / "shell.log"
        self.hyprctl_log = tmp / "hyprctl.log"
        self.hyprlock_log = tmp / "hyprlock.log"
        self.log = tmp / "guard.log"
        for path in (self.status, self.qs_pids, self.qs_cmdlines, self.shell_log,
                     self.hyprctl_log, self.hyprlock_log, self.log):
            path.touch()

        self.config_home = tmp / "config"
        (self.config_home / "quickshell" / "end4-pC").mkdir(parents=True)
        self.env = os.environ.copy()
        self.env.update(
            XDG_RUNTIME_DIR=str(self.rt),
            XDG_CONFIG_HOME=str(self.config_home),
            # The live unit used to hardcode wayland-1 while the session is on
            # wayland-2; the guard must discover the live socket itself.
            WAYLAND_DISPLAY="wayland-1",
            PATH=f"{self.bin}:{self.env['PATH']}",
            MOCK_STATUS_FILE=str(self.status),
            MOCK_QS_PID_FILE=str(self.qs_pids),
            MOCK_QS_CMDLINE_FILE=str(self.qs_cmdlines),
            MOCK_SHELL_LOG=str(self.shell_log),
            MOCK_HYPRCTL_LOG=str(self.hyprctl_log),
            MOCK_HYPRLOCK_LOG=str(self.hyprlock_log),
            END4PC_LOCK_GUARD_LOG=str(self.log),
            END4PC_LOCK_GUARD_POLL="0.2",
            END4PC_LOCK_GUARD_WAIT="0.6",
            END4PC_LOCK_GUARD_RETRY="1",
            MOCK_FAIL_SECURE="1" if fail_secure else "0",
        )
        self.proc = None

    def lock_marker(self, value: str = SIGNATURE):
        (self.rt / "end4-pC-locked").write_text(value)

    def wayland_socket(self, name: str):
        path = self.rt / name
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(path))
        return sock

    def start(self):
        self.proc = subprocess.Popen(
            [sys.executable, str(GUARD)],
            env=self.env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=3)

    def lines(self, path: Path):
        return [line for line in path.read_text().splitlines() if line]

    @staticmethod
    def wait_for(predicate, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return True
            time.sleep(0.05)
        return False


class LockGuardTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="lock-guard-test-")
        self.addCleanup(self._tmp.cleanup)
        self.h = GuardHarness(Path(self._tmp.name))
        self.addCleanup(self.h.stop)

    def text(self, path):
        return path.read_text()

    def test_crash_while_locked_clears_hyprland_crash_screen(self):
        """A dead theme shell must not leave Hyprland's crash screen painted."""
        self.h.lock_marker()
        self.h.status.write_text("locked-insecure")
        self.h.start()
        self.assertTrue(self.h.wait_for(
            lambda: "clear_crashed_lockscreen" in self.text(self.h.hyprctl_log)))
        self.assertIn(f"qs -n -p {self.h.config_home}/quickshell/end4-pC",
                      self.text(self.h.shell_log))

    def test_failed_restart_never_falls_back_to_hyprlock(self):
        """No second lock client may be started, even when recovery fails."""
        self.h.lock_marker()
        self.h.status.write_text("locked-insecure")
        self.h.start()
        self.assertTrue(self.h.wait_for(
            lambda: "restarting shell" in self.text(self.h.log)))
        time.sleep(1.5)
        self.assertEqual(self.text(self.h.hyprlock_log), "")

    def test_failed_restart_is_retried_after_cooldown(self):
        """A single failed restart must not strand the session forever."""
        failed = GuardHarness(self.h.tmp / "retry", fail_secure=True)
        self.addCleanup(failed.stop)
        failed.lock_marker()
        failed.status.write_text("locked-insecure")
        failed.start()
        self.assertTrue(failed.wait_for(
            lambda: failed.log.read_text().count("restarting shell") >= 2,
            timeout=8))
        self.assertEqual(failed.hyprlock_log.read_text(), "")

    def test_unlocked_session_is_left_alone(self):
        """An unlocked desktop must never be re-locked by the watchdog."""
        self.h.start()
        time.sleep(1.2)
        self.assertEqual(self.text(self.h.shell_log), "")
        self.assertEqual(self.text(self.h.hyprctl_log), "")
        self.assertEqual(self.text(self.h.hyprlock_log), "")

    def test_already_secure_lock_is_left_alone(self):
        """A healthy themed lock needs no restart."""
        self.h.lock_marker()
        self.h.status.write_text("locked-secure")
        self.h.qs_pids.write_text("4242\n")
        self.h.start()
        time.sleep(1.2)
        self.assertEqual(self.text(self.h.shell_log), "")
        self.assertEqual(self.text(self.h.hyprctl_log), "")

    def test_legacy_bridge_markers_are_ignored(self):
        """Markers from the removed hyprlock bridge must not revive it."""
        (self.h.rt / "end4-pC-hyprlock-bridge").write_text(SIGNATURE)
        (self.h.rt / "end4pc-lock-guard-fallback").write_text("1")
        self.h.start()
        time.sleep(1.2)
        self.assertEqual(self.text(self.h.hyprlock_log), "")
        self.assertEqual(self.text(self.h.shell_log), "")

    def test_path_based_shell_is_detected(self):
        """The live shell uses `-n -p <path>`; it must not be killed/restarted."""
        self.h.qs_cmdlines.write_text(
            f"/usr/bin/qs -n -p {self.h.config_home}/quickshell/end4-pC\n")
        self.h.lock_marker()
        self.h.status.write_text("locked-secure")
        self.h.start()
        time.sleep(1.2)
        self.assertEqual(self.text(self.h.shell_log), "")

    def test_ipc_probes_are_not_counted_as_the_shell(self):
        """Short-lived IPC calls must not be mistaken for a running shell."""
        self.h.qs_cmdlines.write_text(
            "/usr/bin/qs -c end4-pC ipc call lock status\n")
        self.h.lock_marker()
        self.h.status.write_text("locked-insecure")
        self.h.start()
        self.assertTrue(self.h.wait_for(
            lambda: "restarting shell" in self.text(self.h.log)))
        self.assertEqual(self.text(self.h.hyprlock_log), "")

    def test_default_log_lives_in_user_state_dir(self):
        """The user service must not depend on a root-owned /tmp log file."""
        state = self.h.tmp / "state" / "nested"
        self.h.env.pop("END4PC_LOCK_GUARD_LOG", None)
        self.h.env["XDG_STATE_HOME"] = str(state)
        self.h.start()
        log_path = state / "end4pc-lock-guard.log"
        self.assertTrue(self.h.wait_for(
            lambda: log_path.exists() and "guard started" in log_path.read_text()))
        self.h.stop()

    def test_wayland_display_follows_live_socket(self):
        """A stale wayland-1 in the unit must not send qs to the wrong display."""
        self.addCleanup(self.h.wayland_socket("wayland-1").close)
        self.addCleanup(self.h.wayland_socket("wayland-2").close)
        self.h.lock_marker()
        self.h.status.write_text("locked-insecure")
        self.h.start()
        self.assertTrue(self.h.wait_for(
            lambda: "clear_crashed_lockscreen" in self.text(self.h.hyprctl_log)))
        self.assertIn("WAYLAND_DISPLAY=wayland-2", self.text(self.h.hyprctl_log))


if __name__ == "__main__":
    unittest.main(verbosity=2)
