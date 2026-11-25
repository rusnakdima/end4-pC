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
- Lock-on-disconnect using the **end4-pC Quickshell lock screen** (on by
  default), plus optional idle inhibition. Connecting never unlocks.
- Optional wallpaper suppression while a client is connected (desktop image,
  video, centered image and lock wallpaper).
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

The bind mode is selected in **Settings → VNC → Network & Security**:

| Mode | Addresses | Use |
|---|---|---|
| Automatic (default) | `127.0.0.1`, every physical Ethernet/Wi-Fi IPv4, and the Tailscale IPv4 | Local SSH tunnel, same LAN, and the private tailnet at the same time. |
| Custom | One address you type | A single interface or `0.0.0.0` when you deliberately want all interfaces. |

Examples (replace `<port>` with the port shown in **Settings → VNC**; the
default is `5900`):

```bash
# SSH tunnel from anywhere
ssh -L <port>:127.0.0.1:<port> user@host
# then connect the VNC client to localhost:<port>

# Same Ethernet/Wi-Fi network
vncviewer <ethernet-ip>:<port>
vncviewer <wifi-ip>:<port>

# Tailscale / VPN
vncviewer <tailscale-ip>:<port>
```

X11 viewers need `DISPLAY`. Shells started inside the graphical session
inherit it automatically; if you launch a viewer from a TTY or a script,
source the helper shipped with end4-pC first (it picks the X socket owned
by your user, falling back to `:1`):

```bash
. /path/to/end4-pC/scripts/gui-env.sh
```

In every case, accept the self-signed certificate fingerprint shown in
Settings → VNC → Network & Security on first connect.

## Security

- TLS authentication is enabled by default. Automatic bind mode refuses to
  start without authentication because it exposes LAN and Tailscale addresses.
- PAM is available and uses the system password; otherwise a VNC password is
  stored in `vnc.secret` with mode `600`. It is never printed by `status` and
  never returned to the Settings page.
- If authentication is disabled, only a loopback bind is allowed.
- UFW must allow the port on each exposed interface. Run once as root:
  ```bash
  sudo ~/.local/bin/end4pc-vnc-firewall <port>
  ```
  This allows `lo`, `tailscale0`, and every physical `en*`/`eth*`/`wl*`/
  `wlan*` interface. It deliberately does not open docker, libvirt, or the
  hotspot interface.
- The self-signed certificate is intentionally local; compare its SHA256
  fingerprint on first connect.

## Settings page

**Settings → VNC** controls:

- service start/stop/restart and autostart;
- capture mode, output, FPS, cursor, GPU, resizing;
- automatic or custom bind mode, port, TLS, username, password, certificate, PAM;
- detected loopback, Ethernet/Wi-Fi and Tailscale addresses with firewall hints;
- remote input and keyboard layout;
- **Lock on disconnect** (on by default, uses the theme lock and never unlocks on connect),
  idle inhibition, exit-on-disconnect, log level;
- **Hide wallpaper while a client is connected** (on by default);
- a **Clients** block with per-session monitoring (user, address, access kind,
  interface, seat, connection time, uptime), per-client **Details** spoilers,
  disconnect, disconnect-all and refresh;
- an **Outputs** block with the monitor description, size, power state and a
  live **Capture now** switch;
- diagnostics, SSH tunnel command and logs.

The page stages VNC changes and sends one JSON patch to the controller. The
controller validates, writes atomically and restarts the user service when
needed. The wallpaper switch is the one exception: it writes the shell setting
`background.vnc.disableWallpaper` directly, like the other theme settings. The
page never restarts Quickshell.

## Wallpaper suppression

With **Settings → VNC → Behaviour → Hide wallpaper while a client is connected**
enabled (default), the desktop falls back to a solid theme color for as long as
at least one VNC client is connected: the image layer is cleared, the video is
paused, and the centered and lock-screen wallpapers are hidden too. Everything
is restored when the last client disconnects. A manual pause or the battery
pause policy is kept separate, so neither canceling the other.

The controller watches `wayvncctl event-receive` and publishes connection state
on change to `$XDG_RUNTIME_DIR/end4pc-vnc-clients.json`. The shell reads that
small file instead of polling the full status command. Diagnostics:

```bash
cat "$XDG_RUNTIME_DIR/end4pc-vnc-clients.json"
qs -c end4-pC ipc call vnc status
qs -c end4-pC ipc call livewallpaper status
```

## Interactive configurator over SSH

The same controller has a text menu built for SSH:

```bash
ssh -t user@host
vnc-configurator
# or
end4pc-vnc menu
```

It covers the service, bind mode, port, TLS/PAM/password, capture, encoding,
input, behaviour, clients, live output switching and logs. Changes are staged;
the menu applies them through the same validated controller as the Settings
page. It needs a TTY (`ssh -t`) for prompts and password entry.

## CLI

```bash
~/.local/bin/end4pc-vnc status
~/.local/bin/end4pc-vnc apply --stdin < settings.json
~/.local/bin/end4pc-vnc service start|stop|restart
~/.local/bin/end4pc-vnc service autostart-on|autostart-off
~/.local/bin/end4pc-vnc password          # reads the password from stdin
~/.local/bin/end4pc-vnc cert regenerate
~/.local/bin/end4pc-vnc clients          # user, address, access kind, seat, uptime
~/.local/bin/end4pc-vnc outputs          # name, description, size, power, capture
~/.local/bin/end4pc-vnc disconnect <id>
~/.local/bin/end4pc-vnc disconnect-all
~/.local/bin/end4pc-vnc output-set HDMI-A-2
~/.local/bin/end4pc-vnc desktop-name "end4-pC"
~/.local/bin/end4pc-vnc log -n 200
~/.local/bin/end4pc-vnc menu        # interactive configurator
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
- `ss -ltnp | grep 5900` (or your configured port)
- If the input is view-only, check **Allow remote input** and that the
  compositor accepted virtual keyboard/pointer devices.
- If the screen is locked and the remote is black, the compositor may block
  screen capture during `ext-session-lock`; unlock locally or use a separate
  capture stack.
