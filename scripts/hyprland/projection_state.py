#!/usr/bin/env python3
"""Read/write the saved Windows-style display projection state.

The shell never writes the compositor config from QML: the projection pane
keeps its mode, placement and the pre-projection layout here, and
MonitorConfigOption applies that state to Hyprland and monitors.lua.

Usage:
    projection_state.py --get
    projection_state.py --set mode placement '{"eDP-1": {...}}'
"""

import argparse
import json
import os
import tempfile

DEFAULT = {"mode": "", "placement": "right", "bases": {}}


def state_path():
    return os.path.expanduser("~/.config/end4-pC/projection.json")


def read():
    try:
        with open(state_path()) as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return dict(DEFAULT)
        result = dict(DEFAULT)
        for key in DEFAULT:
            if key in data:
                result[key] = data[key]
        if not isinstance(result["bases"], dict):
            result["bases"] = {}
        return result
    except (OSError, ValueError):
        return dict(DEFAULT)


def write(mode, placement, bases):
    data = {"mode": mode, "placement": placement, "bases": bases}
    path = state_path()
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=directory, delete=False) as f:
        json.dump(data, f, sort_keys=True)
        tmp = f.name
    os.replace(tmp, path)
    print(json.dumps(data))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--get", action="store_true", help="print the saved state as JSON")
    parser.add_argument("--set", nargs=3, metavar=("MODE", "PLACEMENT", "BASES_JSON"),
                        help="save mode, placement and the pre-projection layout")
    args = parser.parse_args()
    if args.set:
        mode, placement, bases_json = args.set
        try:
            bases = json.loads(bases_json)
            if not isinstance(bases, dict):
                raise ValueError("bases must be an object")
        except ValueError as exc:
            parser.error("invalid bases JSON: %s" % exc)
        write(mode, placement, bases)
    else:
        print(json.dumps(read()))


if __name__ == "__main__":
    main()
