#!/usr/bin/env python3
"""Offline tests for the end4pc-vnc TLS certificate generation."""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "optional/vnc/bin/end4pc-vnc"


class End4pcVncTlsTest(unittest.TestCase):
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
            loader = importlib.machinery.SourceFileLoader("end4pc_vnc", str(SCRIPT))
            spec = importlib.util.spec_from_loader(loader.name, loader)
            self.mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.mod)

    def test_san_covers_every_detected_address_and_hostname(self):
        mod = self.mod
        detected = [
            {"address": "127.0.0.1", "kind": "loopback", "interface": "lo"},
            {"address": "192.168.71.86", "kind": "lan", "interface": "enp1s0"},
            {"address": "100.90.92.21", "kind": "tailscale", "interface": "tailscale0"},
        ]
        cfg = {
            "network": {
                "auth": True,
                "bindMode": "custom",
                "address": "10.12.91.180",
            }
        }
        commands = []

        def fake_run(cmd, **kwargs):
            commands.append(cmd)
            Path(cmd[cmd.index("-keyout") + 1]).write_text("key", encoding="utf-8")
            Path(cmd[cmd.index("-out") + 1]).write_text("cert", encoding="utf-8")
            return 0, "", ""

        with patch.object(mod, "detected_addresses", return_value=detected), \
             patch.object(mod.socket, "gethostname", return_value="archpc"), \
             patch.object(mod.socket, "getfqdn", return_value="archpc.tailcfcc7f.ts.net"), \
             patch.object(mod, "run", side_effect=fake_run):
            mod.ensure_tls(cfg)

        self.assertEqual(len(commands), 1)
        ext = commands[0][commands[0].index("-addext") + 1]
        self.assertTrue(ext.startswith("subjectAltName="))
        sans = set(ext.split("=", 1)[1].split(","))
        expected = {
            "DNS:localhost",
            "IP:127.0.0.1",
            "IP:::1",
            "IP:192.168.71.86",
            "IP:100.90.92.21",
            "IP:10.12.91.180",
            "DNS:archpc",
            "DNS:archpc.tailcfcc7f.ts.net",
        }
        self.assertTrue(expected.issubset(sans), f"missing SANs: {sorted(expected - sans)}")


if __name__ == "__main__":
    unittest.main()
