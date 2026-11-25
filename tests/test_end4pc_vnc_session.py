#!/usr/bin/env python3
"""Offline tests for end4pc-vnc Wayland session attachment."""

import importlib.machinery
import importlib.util
import os
import socket
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "optional/vnc/bin/end4pc-vnc"


class End4pcVncSessionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        env = {
            "HOME": self.tmp.name,
            "XDG_CONFIG_HOME": str(Path(self.tmp.name) / "config"),
            "XDG_RUNTIME_DIR": str(Path(self.tmp.name) / "runtime"),
            "USER": "dmitriy",
        }
        with patch.dict(os.environ, env):
            loader = importlib.machinery.SourceFileLoader("end4pc_vnc_session", str(SCRIPT))
            spec = importlib.util.spec_from_loader(loader.name, loader)
            self.mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.mod)

    def test_wayland_display_picks_newest_socket_in_runtime(self):
        runtime = Path(self.tmp.name) / "runtime"
        runtime.mkdir(parents=True)
        for name, mtime in (("wayland-1", 1000), ("wayland-2", 2000)):
            path = runtime / name
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(path))
            sock.close()
            os.utime(path, (mtime, mtime))

        self.assertEqual(self.mod.wayland_display(runtime), "wayland-2")

    def test_wayland_display_falls_back_without_sockets(self):
        runtime = Path(self.tmp.name) / "runtime"
        runtime.mkdir(parents=True)
        self.assertEqual(self.mod.wayland_display(runtime), "wayland-1")


if __name__ == "__main__":
    unittest.main()
