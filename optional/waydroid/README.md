# optional/waydroid — Waydroid for end4-pC (archpc-style)

Optional module that sets up [Waydroid](https://waydro.id/) so it behaves like
the reference device **archpc**: Android boots on Hyprland login, apps appear as
desktop windows, `.desktop` entries exist, Play Store included.

**Off by default.** Nothing in a normal `install.sh` run touches Waydroid.

## Enable it

```bash
# via the theme installer (flag is non-default)
./install.sh --with-waydroid

# or standalone, repeatedly / any time
./optional/waydroid/install-waydroid.sh
```

Root steps use `sudo`; on machines with the standard end4 sudoers NOPASSWD
subset (`tee`, `mkdir`, `install`, `pacman`, `systemctl`), cfg edits and
package installs run passwordless. The setup also installs passwordless rules
for a small root-only wrapper (`/usr/local/bin/waydroid-root`, allowing only
`init|upgrade|container|shell|logcat`) and for the NVIDIA helpers, so **no
Waydroid command ever needs to run the session as root**.

Everything a user launches goes through `~/.local/bin/waydroid-user-start`,
which runs as the desktop user, starts the Venus render server as a
`systemd --user` service, forces the user's runtime dir/bus, and waits for
both Session and Container to be RUNNING.

## What it does

1. **Package** — picks per hardware:
   - NVIDIA GPU → AUR `waydroid-a17-nvidia-bin` (Android 17 + NV acceleration;
     stock waydroid has poor NVIDIA support)
   - otherwise → stock `waydroid` from extra, exactly like archpc
2. **Images/init**
   - fork: stages the [WayDroid-ATV](https://github.com/WayDroid-ATV/waydroid-builds)
     GAPPS system image + the vendor image packaged inside the AUR package into
     `/etc/waydroid-extra/images` (the fork's `waydroid init -f` auto-detects
     that directory), then runs `waydroid-nvidia-setup` (GPU gate)
   - stock: `waydroid init -s GAPPS` (GAPPS like archpc)
3. **EROFS mountability** — ATV system images are EROFS. If the running kernel
   has no erofs module (partial upgrade, reboot pending) the script installs
   `erofsfuse` so `mount(8)`'s FUSE fallback works; after a reboot the module
   autoloads natively.
4. **cfg reconciliation** — `suspend_action=freeze`, `background_start=true`
   (archpc parity), plus repair of the fork's `vendor_ota` when its GitHub
   release URL starts 404ing (falls back to the `file://` JSON shipped inside
   the package). See `config/waydroid.cfg.ref` for the annotated reference.
5. **Hyprland integration** — appends three marker-guarded snippets into the
   user-owned `~/.config/hypr/custom/` (never overwritten by theme updates):
   - `execs.lua` → autostart intentionally disabled (the Venus user unit is
     the proper login-time startup; Waydroid starts on first use)
   - `rules.lua` → Android app windows float phone-shaped (`class = ^waydroid\.`)
   - `keybinds.lua` → `SUPER+CTRL+A` full UI, `SUPER+CTRL+SHIFT+A` regen desktops
     (both combos verified conflict-free against the theme's own binds)
6. **User privileges** — enables/starts `wd-venus.service` as a user unit,
   installs the `waydroid-root` whitelist wrapper, NOPASSWD sudoers rules, and
   `~/.local/bin/waydroid-user-start`.
7. **Session** — starts Waydroid as the desktop user on the detected Wayland
   socket via the helper, enables `persist.waydroid.multi_windows` (fork: one
   desktop window per app), and regenerates `.desktop` entries via
   `scripts/waydroid-desktop-gen.sh` (which uses the user-level
   `waydroid app list`, never root-only `waydroid shell`).
8. **Verify** — session/container RUNNING, apps listed, Play Store present.

## Known gotchas this module encodes

| Gotcha | Handling |
|---|---|
| Android 17 vendor + official lineage-20 system = bootloop (`VINTF manifest.version 9.0 (libvintf@5.0)`, gralloc symbol errors) | fork path uses the **ATV lineage-24** system image only |
| `waydroid upgrade` only swaps an image when `response.datetime > cfg system_datetime` — an older channel is a silent no-op | cfg ref documents `system_datetime = 0` reset |
| fork's `vendor_ota` GitHub release gets pruned → 404 breaks `waydroid upgrade` | auto-switch to packaged `file://…json` |
| EROFS system.img on a kernel without the erofs module | installs `erofsfuse` fallback |
| `waydroid session start` needs `WAYLAND_DISPLAY` | detects `/run/user/<uid>/wayland-*` |
| Waydroid log/`shell`/`upgrade` are root-gated; sessions refuse `sudo` | root work only via the `waydroid-root` whitelist + NOPASSWD; sessions/launchers run as the user through `waydroid-user-start` |
| `nvidia_driver_mode=venus` needs `/run/waydroid-venus/venus.sock` | `wd-venus.service` is enabled as a user unit and started by the helper |
| A17 system + MAINLINE vendor image are ABI-incompatible (missing HIDL symbols): guest never finishes booting, so apps cannot be listed/launched even though Session/Container are RUNNING | known limitation — host user-mode works; the QML panel reports this honestly; needs a matching vendor image (and a supported NVIDIA driver, e.g. 615.78.08) to fix |
| old `dots/hyprland/*.lua` snippets used nonexistent APIs (`hl.keybind`, 2-table `window_rule`) and conflicting binds | superseded by these snippets (real `hl.bind` / single-table `hl.window_rule`, free combos) |

## Disable / remove

Snippets are marker-guarded — delete the blocks between
`-- >>> waydroid-…` and `-- <<< waydroid-…` in
`~/.config/hypr/custom/{execs,rules,keybinds}.lua`.
Waydroid itself: `sudo systemctl disable --now waydroid-container && sudo pacman -Rns waydroid`.

## Reference

- archpc: stock `waydroid 1.6.3`, GAPPS `lineage-20.0-…-GAPPS`, `suspend_action=freeze`,
  autostart in `custom/execs.lua`, 13 auto-generated `waydroid.*.desktop` entries.
- This module on NVIDIA hardware: fork = Android 17 `lineage-24.0-…-GAPPS` (WayDroid-ATV)
  + `waydroid-nvidia-vendor`, `multi_windows=true`, per-app windows.
