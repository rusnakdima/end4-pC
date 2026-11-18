# end4-pC VNC (user-level)

A VNC server for the **existing** Hyprland session. It does not start a second
compositor, does not use VKMS, and does not touch `/etc`, seatd, PipeWire
runtime paths or the end4-pC shell configuration.

```text
remote client
   │  TLS VNC / SSH tunnel / Tailscale
   ▼
wayvnc  (systemd --user service)
   │  captures the existing monitor(s), injects input into the same seat
   ▼
Hyprland (single instance) ── Quickshell, PipeWire, lock screen
```

## What it supports

- All physical monitors as one stream (`-a`) or one selected monitor (`-o`).
- TLS authentication with a self-signed certificate and a VNC password
  (or PAM authentication).
- Bind to loopback, a Tailscale address, or another local address.
- Render cursor, FPS limit, GPU option, client resize control, view-only mode.
- Match the host keyboard layout, or override the XKB settings.
- Runtime output switching and per-client disconnect.
- Optional lock-on-disconnect / idle inhibition.
- A full Settings page under **Settings → VNC**.

Not supported:

- A virtual “mirror” output. On Hyprland 0.57 wayvnc cannot capture a mirrored
  headless output; use all monitors or one physical output.
- Audio. VNC carries no audio; use Sunshine/Moonlight or a separate audio
  transport if you need sound.

## Install

Run as the desktop user:

```bash
./optional/vnc/install-user.sh
```

This installs:

- `~/.local/bin/end4pc-vnc`
- `~/.config/systemd/user/wayvnc.service`
- `~/.config/end4-pC/vnc.json`
- `~/.config/end4-pC/vnc.secret` (mode 600)
- `~/.config/end4-pC/vnc/tls/{cert,key}.pem`
- a generated `wayvnc` config under the same directory

It does **not** enable the service by default. Enable it from the VNC Settings
page, or:

```bash
systemctl --user enable --now wayvnc.service
```

The installer generates a random VNC password in
`~/.config/end4-pC/vnc.secret` (mode 600). Set your own password in
**Settings → VNC → Network & Security** before connecting, or read that file
locally and replace it from Settings.

The service binds to `127.0.0.1:5900` by default. Connect through SSH:

```bash
ssh -L 5900:127.0.0.1:5900 user@host
```

Then point the VNC client at `localhost:5900` and accept the certificate
fingerprint shown in Settings → VNC → Network & Security.

## Security

- TLS authentication and a VNC password are enabled by default.
- The password is stored in `vnc.secret` with mode `600`; it is never printed by
  `status` and never returned to the Settings page.
- If authentication is disabled, the controller refuses any bind address that
  is not loopback.
- Do not expose port 5900 directly to the LAN/WAN. Prefer an SSH tunnel or a
  Tailscale bind (the Settings page lists the detected Tailscale address).
- The self-signed certificate is intentionally local; compare its SHA256
  fingerprint on first connect.

## Settings page

**Settings → VNC** controls:

- service start/stop/restart and autostart;
- capture mode, output, FPS, cursor, GPU, resizing;
- bind address, port, TLS, username, password, certificate, PAM;
- remote input and keyboard layout;
- lock-on-disconnect, idle inhibition, exit-on-disconnect, log level;
- connected clients, outputs, diagnostics, SSH tunnel command and logs.

The page stages changes and sends one JSON patch to the controller. The
controller validates, writes atomically and restarts the user service when
needed. The page never writes `~/.config/illogical-impulse/config.json` and
never restarts Quickshell.

## CLI

```bash
~/.local/bin/end4pc-vnc status
~/.local/bin/end4pc-vnc apply --stdin < settings.json
~/.local/bin/end4pc-vnc service start|stop|restart
~/.local/bin/end4pc-vnc service autostart-on|autostart-off
~/.local/bin/end4pc-vnc password          # reads the password from stdin
~/.local/bin/end4pc-vnc cert regenerate
~/.local/bin/end4pc-vnc clients
~/.local/bin/end4pc-vnc outputs
~/.local/bin/end4pc-vnc output-set HDMI-A-2
~/.local/bin/end4pc-vnc desktop-name "end4-pC"
~/.local/bin/end4pc-vnc log -n 200
```

The QML singleton also exposes `qs -c end4-pC ipc call vnc refresh` and
`... ipc call vnc applyCurrent` for diagnostics.

## Uninstall

```bash
./optional/vnc/uninstall-user.sh          # keeps config/TLS/password
./optional/vnc/uninstall-user.sh --purge  # removes config/TLS/password too
```

## Legacy installer

`install-vnc.sh` is the old full/hidden VKMS setup. It is **retired** and exits
unless `END4PC_VNC_LEGACY=1` is set. It created a second Hyprland session and
was the source of the earlier audio/config/lock problems. The old documentation
is preserved as `README-legacy.md`; do not use it for new installs.

## Troubleshooting

- `systemctl --user status wayvnc.service`
- `journalctl --user -u wayvnc.service -n 200 --no-pager`
- `~/.local/bin/end4pc-vnc validate`
- `ss -ltnp | grep 5900`
- If the input is view-only, check **Allow remote input** and that the
  compositor accepted virtual keyboard/pointer devices.
- If the screen is locked and the remote is black, the compositor may block
  screen capture during `ext-session-lock`; unlock locally or use a separate
  capture stack.
