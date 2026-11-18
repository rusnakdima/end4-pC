# end4pc-cast helper (CLI contract)

`end4pc-cast` is a Python 3 standard-library-only CLI. The QML Cast service
calls it and parses **stdout as a single JSON object**. Every command — including
errors, missing backends and bad arguments — prints valid JSON and never a
traceback on stdout. Diagnostics live in `error`, `doctor` and `logTail`.

`status` is fast and read-only: it works with zero backends installed and
reports `installed:false`, `session.active:false` and actionable doctor entries.

## Commands

| Command | Effect |
| --- | --- |
| `end4pc-cast status` | Print the full status object. No side effects. |
| `end4pc-cast apply '<json patch>'` | Deep-merge the patch into the config, write `~/.config/end4-pC/cast/config.json` atomically, print status. Also accepts `--stdin`. |
| `end4pc-cast discover --network-mode local\|remote` | Discover TVs, cache the sink list, print status. Local: `waycast discover --timeout 10`. Remote: Avahi (`avahi-browse -art _dlna._tcp`, `_googlecast._tcp`, `_airplay._tcp`) and/or `fluxcast discover`. |
| `end4pc-cast start` | Launch the selected backend, track its PID in `session.json`, redirect output to `cast.log`, print status. |
| `end4pc-cast stop` | Terminate the tracked process (SIGTERM, then SIGKILL), clear the session, print status. |
| `end4pc-cast restart` | Stop then start, print status once. |
| `end4pc-cast log [-n N]` | Print `{"ok":true,"error":"","text":"..."}` with the last N log lines (default 200). |

Backend selection is derived from `config.networkMode`: `local` → **waycast**
(Miracast / Wi-Fi Direct), `remote` → **fluxcast** (LAN/Tailscale DLNA / Cast).

## Status JSON schema

```json
{
  "ok": true,
  "error": "",
  "helperVersion": 1,
  "config": {
    "networkMode": "local",
    "mode": "mirror",
    "codec": "auto",
    "audio": true,
    "target": "",
    "interface": ""
  },
  "backends": {
    "waycast":  { "installed": true, "version": "" },
    "fluxcast": { "installed": false, "version": "" }
  },
  "session": {
    "active": false,
    "backend": "",
    "sink": "",
    "mode": "mirror",
    "startedAt": "",
    "pid": 0
  },
  "sinks": [
    { "name": "Living Room TV", "address": "192.168.1.50", "type": "dlna" }
  ],
  "doctor": [
    { "id": "p2p", "label": "Wi-Fi Direct", "ok": true, "detail": "..." }
  ],
  "logTail": ""
}
```

Field notes:

- `config.networkMode`: `local` (Miracast/Wi-Fi Direct) or `remote`
  (LAN/Tailscale DLNA/Cast). `mode`: `mirror` or `extend`. `codec`: `auto`,
  `h264` or `h264-sw`. `audio`: boolean. `target`: manual TV address for remote
  mode. `interface`: optional Wi-Fi interface.
- `session.active` is computed from the tracked PID (verified via `/proc` when
  available), so a dead backend never reports as active.
- `sinks[].type` is one of `wfd`, `dlna`, `cast`.
- `doctor[].id` values: `hyprland`, `portal`, `p2p`, `waycast`, `fluxcast`,
  `encoder`, `gstreamer`, `audio`. Detail strings are actionable.

## Backend command lines

Local (`waycast`):

```
waycast daemon --sink <sink> [--extend] [--codec h264|h264-sw] [--no-audio] [--interface <iface>]
```

Remote (`fluxcast`):

```
fluxcast --protocol dlna --transport hls [--target <target>]
fluxcast --protocol cast [--target <target>]
```

`--codec` is omitted for `auto`; `--extend` is added only for extend mode;
`--no-audio` only when `audio` is false. For fluxcast, the target flag is only
passed when `fluxcast --help` shows a supported one (`--target`, `--device`,
`--url`, `--host`, `--address`, `--sink`) so an unsupported flag is never
invented.

## State files

All under `${XDG_CONFIG_HOME:-~/.config}/end4-pC/cast/`:

| File | Contents |
| --- | --- |
| `config.json` | Persisted configuration (written atomically). |
| `session.json` | Tracked backend, sink, mode, start time and PID. |
| `sinks.json` | Cached discovery results. |
| `cast.log` | Backend stdout/stderr, appended across starts. |

Waycast built from source lives in
`${XDG_DATA_HOME:-~/.local/share}/end4pc-cast/waycast/waycast`.
