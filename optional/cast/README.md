# end4-pC Cast (user-level)

Cast the **existing** Hyprland desktop to a TV. No second compositor, no VKMS,
no seatd changes and no edits to `/etc` by the installer.

```text
TV (Miracast / DLNA / ChromeCast)
   │  Wi-Fi Direct (local)  or  LAN / Tailscale (remote)
   ▼
waycast (local)  /  fluxcast (remote)
   │  captures the running Hyprland session, sends H.264 + audio
   ▼
Hyprland (single instance) ── Quickshell, PipeWire, lock screen
```

The QML Settings page talks only to `~/.local/bin/end4pc-cast`, which prints one
JSON object per command. See `../../scripts/cast/README.md` for the full CLI /
JSON contract.

## Modes

- **local** — Miracast over Wi-Fi Direct (P2P). Backend: `waycast`. Needs a
  P2P-capable Wi-Fi device and a wpa_supplicant P2P configuration (root step
  printed by the installer, never executed automatically).
- **remote** — DLNA or Google Cast over LAN / Tailscale. Backend: `fluxcast`.
  Uses Avahi discovery and a manual `target` address if auto-discovery fails.
  Port `7236/tcp` is used for control/RTSP.

Both modes support mirror/extend, `auto`/`h264`/`h264-sw` codec and optional
audio.

## Install

Run as the desktop user:

```bash
./optional/cast/install-user.sh
```

This is idempotent and installs/creates:

- `~/.local/bin/end4pc-cast` (the Python 3 helper)
- `~/.config/end4-pC/cast/config.json` (defaults, kept if you already have one)
- `~/.config/end4-pC/cast/p2p-supplicant.conf` (P2P template, editable)

It also imports `WAYLAND_DISPLAY` and `XDG_CURRENT_DESKTOP` into the systemd
user environment so a backend can reach the compositor. It **does not** install
packages, enable services, start a cast session or run any `sudo` command.

### Backends

Neither backend is forced on you; the installer detects them and prints how to
get them:

- waycast (local): put `waycast` on `PATH`, or build it from a Rust source tree:
  ```bash
  ./optional/cast/install-user.sh --build-waycast /path/to/waycast-src
  # or: WAYCAST_SRC=/path/to/waycast-src ./optional/cast/install-user.sh --build-waycast
  ```
  The binary is installed to
  `~/.local/share/end4pc-cast/waycast/waycast` (needs `cargo`).
- fluxcast (remote): put `fluxcast` on `PATH` (or under
  `~/.local/share/end4pc-cast/fluxcast/`). `avahi-utils` improves discovery.

### Manual root steps (printed, not run)

After editing `~/.config/end4-pC/cast/p2p-supplicant.conf` (set your country
code and Wi-Fi interface):

```bash
sudo install -Dm600 ~/.config/end4-pC/cast/p2p-supplicant.conf /etc/wpa_supplicant/p2p.conf
sudo wpa_supplicant -B -i <wifi-iface> -c /etc/wpa_supplicant/p2p.conf
sudo ufw allow 7236/tcp comment 'end4pc cast'
```

Replace `<wifi-iface>` with your device from `iw dev`. Prefer a LAN/Tailscale
bind for remote mode over exposing the port to the WAN.

## Readiness check

```bash
./optional/cast/install-user.sh --check
```

Reports helper/config presence, detected backends and optional tools. It makes
no changes. Missing backends/tools are warnings (the helper degrades
gracefully); a missing helper, config dir, config file or `python3` is a FAIL.

## CLI

```bash
~/.local/bin/end4pc-cast status
~/.local/bin/end4pc-cast apply '{"networkMode":"local","mode":"mirror","codec":"auto","audio":true,"interface":"wlan0"}'
~/.local/bin/end4pc-cast discover --network-mode local
~/.local/bin/end4pc-cast discover --network-mode remote
~/.local/bin/end4pc-cast start
~/.local/bin/end4pc-cast stop
~/.local/bin/end4pc-cast restart
~/.local/bin/end4pc-cast log -n 200
```

`apply` also accepts `--stdin`. All commands print the status JSON, except `log`
which prints `{"ok":true,"error":"","text":"..."}`.

## Uninstall

```bash
./optional/cast/uninstall-user.sh          # stops session, removes helper, keeps config
./optional/cast/uninstall-user.sh --purge  # also removes config + local build dir
```

The install script also supports `--uninstall` as a shortcut. Neither removes
the manual `/etc` or `ufw` changes.

## Troubleshooting

- `~/.local/bin/end4pc-cast status` — check `doctor` for actionable details.
- `~/.local/bin/end4pc-cast log -n 200` — read the backend log.
- `iw dev` / `iw list` — confirm a P2P-capable Wi-Fi device exists.
- `avahi-browse -art _dlna._tcp` — confirm LAN TVs are discoverable.
- Local mode fails with "no sink selected" → run `discover --network-mode local`
  first, or pass a sink via `apply '{"sink":"..."}'`.
- Remote target ignored → check `fluxcast --help` for the supported target flag;
  the helper never invents flags.
- If the screen is locked and capture is black, unlock locally (compositors may
  block screen capture during `ext-session-lock`).
