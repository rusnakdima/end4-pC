#!/usr/bin/env python3
"""Offline unit tests for scripts/cast/end4pc-cast.

No backend, Wi-Fi device or Wayland session is needed: only pure config/argv
helpers are exercised. Run with the repository test runner:

    tests/run-python-tests.sh
"""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join(REPO, "scripts", "cast", "end4pc-cast")

# The helper deliberately has no .py extension (it is installed as an
# executable named `end4pc-cast`), so use an explicit SourceFileLoader.
loader = importlib.machinery.SourceFileLoader("end4pc_cast", HELPER)
spec = importlib.util.spec_from_loader("end4pc_cast", loader)
cast = importlib.util.module_from_spec(spec)
loader.exec_module(cast)


class WaycastArgsTests(unittest.TestCase):
    def test_interface_is_global_flag_before_daemon(self):
        cfg = {"interface": "wlan0", "codec": "auto", "audio": True, "mode": "mirror"}
        args = cast.build_waycast_args(cfg, "aa:bb:cc:dd:ee:ff")
        self.assertEqual(args[:5], [
            "--interface", "wlan0", "daemon", "--sink", "aa:bb:cc:dd:ee:ff"
        ])
        # It must not be repeated after the subcommand (clap rejects that).
        self.assertNotIn("--interface", args[5:])

    def test_without_interface_starts_with_daemon(self):
        cfg = {"interface": "", "codec": "auto", "audio": True, "mode": "mirror"}
        args = cast.build_waycast_args(cfg, "aa:bb:cc:dd:ee:ff")
        self.assertEqual(args[:2], ["daemon", "--sink"])

    def test_optional_flags_are_preserved(self):
        cfg = {"interface": "", "codec": "h264-sw", "audio": False, "mode": "extend"}
        args = cast.build_waycast_args(cfg, "aa:bb:cc:dd:ee:ff")
        self.assertIn("--extend", args)
        self.assertEqual(args[args.index("--codec") + 1], "h264-sw")
        self.assertIn("--no-audio", args)

    def test_auto_codec_does_not_emit_codec_flag(self):
        cfg = {"interface": "", "codec": "auto", "audio": True, "mode": "mirror"}
        args = cast.build_waycast_args(cfg, "aa:bb:cc:dd:ee:ff")
        self.assertNotIn("--codec", args)
        self.assertNotIn("--no-audio", args)


class SelectedSinkTests(unittest.TestCase):
    def setUp(self):
        self.saved_loader = cast.load_sinks
        cast.load_sinks = lambda: [
            {"name": "Living Room TV", "address": "aa:bb:cc:dd:ee:ff", "type": "wfd"},
        ]

    def tearDown(self):
        cast.load_sinks = self.saved_loader

    def test_friendly_name_is_resolved_to_p2p_address(self):
        sink = cast.selected_sink({"sink": "Living Room TV", "target": ""})
        self.assertEqual(sink, "aa:bb:cc:dd:ee:ff")

    def test_explicit_address_is_kept(self):
        sink = cast.selected_sink({"sink": "11:22:33:44:55:66", "target": ""})
        self.assertEqual(sink, "11:22:33:44:55:66")

    def test_falls_back_to_first_cached_address(self):
        sink = cast.selected_sink({"sink": "", "target": ""})
        self.assertEqual(sink, "aa:bb:cc:dd:ee:ff")

    def test_falls_back_to_target_when_cache_is_empty(self):
        cast.load_sinks = lambda: []
        sink = cast.selected_sink({"sink": "", "target": "192.168.1.50"})
        self.assertEqual(sink, "192.168.1.50")


class ConfigContractTests(unittest.TestCase):
    def test_ui_stream_group_is_flattened(self):
        cfg = cast.normalize_config({
            "stream": {"mode": "extend", "codec": "h264", "audio": False}
        })
        self.assertEqual(cfg["mode"], "extend")
        self.assertEqual(cfg["codec"], "h264")
        self.assertIs(cfg["audio"], False)
        self.assertNotIn("stream", cfg)

    def test_failure_payload_keeps_the_error_for_the_ui(self):
        payload = cast.status_payload(error="no sink selected - run discover first", ok=False)
        self.assertFalse(payload["ok"])
        self.assertIn("no sink selected", payload["error"])
        self.assertFalse(payload["session"]["active"])


class StartSessionTests(unittest.TestCase):
    """Regression tests for live-tested duplicate-start / stale-session bugs."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.saved_dir = cast.CAST_DIR
        self.saved_log = cast.LOG_FILE
        cast.CAST_DIR = Path(self.tmp.name)
        cast.LOG_FILE = Path(self.tmp.name) / "cast.log"
        self.cfg = dict(cast.DEFAULTS)
        self.cfg.update({"networkMode": "remote", "protocol": "cast", "target": "192.168.101.6"})

    def tearDown(self):
        cast.CAST_DIR = self.saved_dir
        cast.LOG_FILE = self.saved_log

    def test_refuses_second_start_while_backend_is_alive(self):
        with patch.object(cast, "load_config", return_value=self.cfg), \
             patch.object(cast, "select_backend", return_value="fluxcast"), \
             patch.object(cast, "find_backend", return_value="/bin/fluxcast"), \
             patch.object(cast, "selected_sink", return_value="192.168.101.6"), \
             patch.object(cast, "load_session", return_value={
                 "active": True, "pid": 4242, "backend": "fluxcast"}), \
             patch.object(cast, "process_alive", return_value=True), \
             patch.object(cast, "build_fluxcast_args", return_value=(["--protocol", "cast"], "")), \
             patch.object(cast.subprocess, "Popen") as popen:
            popen.return_value.pid = 4242
            ok, note = cast.start_session()
        self.assertFalse(ok)
        self.assertIn("already", note.lower())
        popen.assert_not_called()

    def test_clears_stale_session_before_starting(self):
        written = []
        with patch.object(cast, "load_config", return_value=self.cfg), \
             patch.object(cast, "select_backend", return_value="fluxcast"), \
             patch.object(cast, "find_backend", return_value="/bin/fluxcast"), \
             patch.object(cast, "selected_sink", return_value="192.168.101.6"), \
             patch.object(cast, "load_session", return_value={
                 "active": True, "pid": 999999, "backend": "fluxcast"}), \
             patch.object(cast, "process_alive", return_value=False), \
             patch.object(cast, "atomic_write_json",
                          side_effect=lambda path, data: written.append((path, data))), \
             patch.object(cast, "build_fluxcast_args", return_value=(["--protocol", "cast"], "")), \
             patch.object(cast.subprocess, "Popen") as popen:
            popen.return_value.pid = 5555
            ok, note = cast.start_session()
        self.assertTrue(ok)
        self.assertTrue(any(data.get("active") is False for _path, data in written))
        popen.assert_called_once()


class DoctorCheckTests(unittest.TestCase):
    """Regression tests for live-tested doctor false negatives."""

    def test_rtsp_check_admits_it_cannot_verify_as_non_root(self):
        with patch.object(cast.shutil, "which",
                          side_effect=lambda name, *a, **k: "/usr/sbin/ufw" if name == "ufw" else None), \
             patch.object(cast, "find_backend", return_value=""), \
             patch.object(cast, "run",
                          return_value=(1, "", "ERROR: You need to be root to run this script")):
            checks = cast.doctor_checks()
        rtsp = next(c for c in checks if c["id"] == "rtsp")
        self.assertTrue(rtsp["ok"])
        self.assertIn("cannot verify", rtsp["detail"].lower())

    def test_portal_binary_found_outside_path(self):
        with patch.object(cast.shutil, "which", return_value=None), \
             patch.object(cast.os.path, "isfile",
                          side_effect=lambda p: p == "/usr/lib/xdg-desktop-portal"), \
             patch.object(cast.os, "access", return_value=True):
            self.assertEqual(cast.find_portal_binary(), "/usr/lib/xdg-desktop-portal")


if __name__ == "__main__":
    unittest.main()
