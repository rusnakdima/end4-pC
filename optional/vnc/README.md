# Optional VNC remote desktop for end4-pC

This module installs a Tailscale-friendly VNC setup for end4-pC:

- `:5901` — physical session mirror, **interactive**
- `:5902` — separate hidden Hyprland session on VKMS
- optional audio via Sunshine + Moonlight
- optional end4-pC wallpaper blanking and lock-on-disconnect

It is **not** installed by default. Use:

```bash
./install.sh --with-vnc
```

Or run it standalone:

```bash
./optional/vnc/install-vnc.sh
```

## Important: VNC has no audio

VNC does not carry audio. If you connect with Remmina/wayvnc, you will not hear
sound. Audio requires a separate transport:

- **Sunshine + Moonlight** (recommended): video, input, and audio.
- PipeWire/PulseAudio tunnel (manual; not installed by this script).
- VNC only: video and input, **no sound**.

`--vnc-audio=sunshine` installs the null sink and Sunshine configuration and
enables `sunshine-remote.service`. Moonlight still needs to be paired manually.

## Architecture

```text
laptop
  ├─ Remmina :5901 ── physical Hyprland (DP-1 + HDMI-A-2), interactive
  ├─ Remmina :5902 ── hidden Hyprland (Virtual-1 on VKMS), interactive
  └─ Moonlight ────── Sunshine → Virtual-1 + hypr_remote.monitor (audio)
```

The hidden session is a **separate Hyprland compositor**, not a third monitor
inside the host session. The host keeps only its physical monitors.

The hidden session uses:

- VKMS (`/dev/dri/vkms`) as its only DRM output
- a private `seatd` inside a private `/dev` namespace
- private runtime `/run/user/<uid>/remote`
- end4-pC loaded from the real user's `hyprland.lua`

The physical session is pinned to the Intel GPU:
`AQ_DRM_DEVICES=<physical card>` and `LIBSEAT_BACKEND=logind`.

## Requirements

- Arch/CachyOS, Hyprland, end4-pC installed
- `wayvnc`, `seatd`, `jq`, `grim`, `hyprlock`
- `sunshine` for audio (optional)
- `vkms` kernel module
- Tailscale (strongly recommended)
- SDDM or another display manager for the physical session

The installer performs system changes:

- `/etc/modules-load.d/vkms.conf`
- `/etc/udev/rules.d/99-vkms.rules`
- `/etc/environment` (`AQ_DRM_DEVICES`, `LIBSEAT_BACKEND=logind`)
- `/etc/X11/xorg.conf.d/99-intel-only.conf`
- SDDM autologin (unless `--vnc-autologin=0`)
- disables system `seatd` (the hidden service starts its own)
- UFW rules restricted to `100.64.0.0/10` (Tailscale)

Backups are stored in `/var/lib/end4-pC-vnc/backup`.

## Configuration

Copy `vnc.conf.example` to `~/.config/end4-pC/vnc.conf` or set environment
variables before running:

```bash
VNC_USER=dmitriy
VNC_BIND_ADDR=100.90.92.21
VNC_MIRROR_PORT=5901
VNC_HIDDEN_PORT=5902
VNC_AUDIO=sunshine        # sunshine | none
VNC_AUTOLOGIN=1           # 1 | 0
```

If `VNC_BIND_ADDR` is omitted, the installer uses the first Tailscale IPv4
address, or `127.0.0.1` with a warning.

## Audio

After install:

```bash
systemctl --user enable --now sunshine-remote.service
ss -tlnp | grep -E '47984|47989|47990|48010'
```

Open the Sunshine web UI, pair Moonlight, and select the stream. Sound from
apps in the hidden session is routed to `hypr_remote` and captured by Sunshine.
The host speakers remain silent.

## Theme hooks

When a client connects to `:5901`:

- physical live video slows/stops
- static wallpaper is blanked
- only the physical quickshell is restarted

When the last client disconnects:

- wallpaper is restored
- `hyprlock` locks the physical session

Set `VNC_THEME_LOCK=0` in `vnc-theme-hooks.service` to disable locking while
testing.

## Security

- Bind to Tailscale only where possible.
- VNC authentication is disabled by default in this module; rely on Tailscale
  and UFW, or put VNC behind an SSH tunnel.
- Autologin is enabled by default because `:5901` needs a physical session.
  Disable it with `--vnc-autologin=0`; then log in physically first.
- Locking on disconnect is enabled by default.

## Uninstall

```bash
./optional/vnc/uninstall-vnc.sh
```

This disables/removes the units and generated configs and restores the backed-up
system files. It does not remove packages.

## Known limitations

- A single wayvnc `-a` stream captures all physical outputs as one framebuffer.
- VNC password authentication is not enabled by this installer.
- Hidden-session audio requires Sunshine/Moonlight, not VNC.
- The VKMS/private-seatd layout is Arch/CachyOS-specific and should be tested
  after the first reboot.
