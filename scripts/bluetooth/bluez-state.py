#!/usr/bin/env python3
"""Query BlueZ state, or run a Bluetooth action, as one line of JSON.

Quickshell's BlueZ integration can be dead for a whole shell session when
bluetoothd was not ready at process start. This helper gives the QML layer an
independent view of the adapter and devices using bluetoothctl only.

Read-only mode (default): print
    {"available": bool, "enabled": bool, "discovering": bool,
     "devices": [{"address", "name", "icon", "paired", "connected",
                  "battery", "batteryAvailable"}, ...]}
Action mode: run the requested bluetoothctl command(s), then print the same
JSON so the caller can refresh once without a second poll.
"""

import argparse
import concurrent.futures
import json
import re
import subprocess
import sys


FAILURE_RE = re.compile(
    r"\b(?:failed|failure|invalid|not available|no such device|permission denied|"
    r"not supported|cannot be used)\b",
    re.IGNORECASE,
)


def bluetoothctl_result(*args):
    """Run one non-interactive command; report output and any failure text."""
    try:
        result = subprocess.run(
            ["bluetoothctl", "--timeout", "1", *args],
            capture_output=True,
            text=True,
            timeout=6,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"output": "", "error": str(exc) or "Bluetooth command failed."}
    stdout = result.stdout or ""
    stderr = (result.stderr or "").strip()
    if result.returncode != 0 or stderr or FAILURE_RE.search(stdout):
        return {"output": stdout, "error": stderr or stdout.strip() or "Bluetooth command failed."}
    return {"output": stdout, "error": ""}


def bluetoothctl(*args):
    """Run one command for read-only queries; "" on any failure."""
    return bluetoothctl_result(*args)["output"]


def field(text, key):
    match = re.search(r"^\s*" + re.escape(key) + r"\s*(.*)$", text, re.MULTILINE)
    return match.group(1).strip() if match else ""


def query():
    # Each bluetoothctl call waits for its --timeout window before exiting,
    # so run the independent calls concurrently: 1 adapter + 1 list + N info
    # calls would otherwise cost (N + 2) * timeout seconds per poll.
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        show_future = pool.submit(bluetoothctl, "show")
        listing_future = pool.submit(bluetoothctl, "devices")
        show = show_future.result()
        listing = listing_future.result()

        available = re.search(r"^\s*Controller\s+\S+", show, re.MULTILINE) is not None
        state = {
            "available": available,
            "enabled": re.search(r"^\s*Powered:\s*yes", show, re.MULTILINE) is not None,
            "discovering": re.search(
                r"^\s*Discovering:\s*yes", show, re.MULTILINE
            ) is not None,
            "devices": [],
        }
        if not available:
            return state

        addresses = re.findall(r"^Device\s+(\S+)", listing, re.MULTILINE)
        infos = list(pool.map(lambda address: bluetoothctl("info", address), addresses))

    for address, info in zip(addresses, infos):
        battery_match = re.search(
            r"Battery Percentage:\s*0x[0-9a-fA-F]+\s*\((\d+)\)", info
        )
        state["devices"].append(
            {
                "address": address,
                "name": field(info, "Alias:") or field(info, "Name:"),
                "icon": field(info, "Icon:"),
                "paired": field(info, "Paired:") == "yes",
                "connected": field(info, "Connected:") == "yes",
                "battery": int(battery_match.group(1)) / 100 if battery_match else 0,
                "batteryAvailable": battery_match is not None,
            }
        )
    return state


def actions_from_args(args):
    commands = []
    if args.power:
        commands.append(("power", args.power))
    if args.discover:
        commands.append(("scan", "on" if args.discover == "start" else "off"))
    for flag, verb in (
        ("connect", "connect"),
        ("disconnect", "disconnect"),
        ("pair", "pair"),
        ("forget", "remove"),
    ):
        value = getattr(args, flag)
        if value:
            commands.append((verb, value))
    return commands


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--query", action="store_true", help="query only (default)")
    parser.add_argument("--power", choices=("on", "off"))
    parser.add_argument("--discover", choices=("start", "stop"))
    parser.add_argument("--connect", metavar="ADDR")
    parser.add_argument("--disconnect", metavar="ADDR")
    parser.add_argument("--pair", metavar="ADDR")
    parser.add_argument("--forget", metavar="ADDR")
    args = parser.parse_args()

    action_error = ""
    for command in actions_from_args(args):
        outcome = bluetoothctl_result(*command)
        if outcome["error"]:
            action_error = outcome["error"]
            break

    payload = query()
    payload["lastActionError"] = action_error
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
