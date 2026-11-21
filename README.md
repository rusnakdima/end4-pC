



<div align="center">

# 💠 end4-pC

**A personal fork of [illogical-impulse](https://github.com/end-4/dots-hyprland) by [@end-4](https://github.com/end-4)**  
Customized and maintained by **pctrade**

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

</div>

---

## 🎬 Showcase

<p align="center">
  <a href="https://www.youtube.com/watch?v=o0Vsh7eVchs">
    <img src="https://img.youtube.com/vi/o0Vsh7eVchs/maxresdefault.jpg" alt="Material 3 Expressive x Linux" width="85%" style="border-radius: 12px; box-shadow: 0px 10px 30px rgba(0,0,0,0.5);"/>
  </a>
</p>

</div>

---

## 📸 Screenshots
<div align="center">

| 🎵 Lyrics | 🖼️ Online Wallpapers |
|:---:|:---:|
| ![Screenshot 1](screenshots/1.png) | ![Screenshot 2](screenshots/2.png) |
| 🪟 Desktop Widgets | 🔧 Hyprland Configs |
| ![Screenshot 5](screenshots/5.png) | ![Screenshot 6](screenshots/6.png) |
| ⚙️ Configurable Bar | ✨ And More |
| ![Screenshot 3](screenshots/3.png) | ![Screenshot 4](screenshots/4.png) |

</div>

---

## 🎨 Community Presets

Share your whole desktop with one button, or try someone else's in a click.

**[end4-pCpresets](https://github.com/pctrade/end4-pCpresets)** is the community gallery for this shell. Open **Dashboard → Presets**, pick a preset and press **Download** to try it or **Install** to keep it. Made your own? Press **Upload**, choose a screenshot and it is sent for you with one click. The first time, a terminal opens to install the [GitHub CLI](https://cli.github.com) (`gh`) and sign you in, which takes a minute. If you skip that, the shell opens a GitHub page where you drag the folder in instead. Changed your mind? **Remove from gallery** takes your own preset back out.

- 🔒 **Private by design:** nothing is collected from you. The shell only reads public files from GitHub.
- 🧹 **Clean exports:** personal paths, keys and commands are removed before anything is shared.
- ✅ **Every preset is checked** automatically. First-time authors are reviewed by hand, and trusted authors are merged automatically once the check passes.
- 👤 **Yours stays yours:** only the person who shared a preset can change or remove it.

[Browse the gallery](https://github.com/pctrade/end4-pCpresets) · [How to share yours](https://github.com/pctrade/end4-pCpresets#share-your-preset)

---

## ⚡ Installation

> [!NOTE]
> This fork manages its own configuration folder independently — it does **not** overwrite or modify any existing setup. However, it does require [illogical-impulse](https://github.com/end-4/dots-hyprland) to be installed and running.

```bash
cd ~/.config/quickshell/
git clone https://github.com/pctrade/end4-pC.git
killall qs 2>/dev/null; qs -c end4-pC > /dev/null 2>&1 & disown
```

### 📶 Hotspot (Wi-Fi AP)

The bar/sidebar Hotspot toggle needs one-time system provisioning (root helper,
sudoers, NetworkManager rule, regulatory domain). After installing, run:

```bash
cd ~/.config/quickshell/end4-pC/scripts/hotspot
sudo ./setup-hotspot.sh        # install (idempotent)  ·  ./setup-hotspot.sh --check  ·  --uninstall
```

Full guide — hardware paths (onboard MT7922 vs AIC8800D80 dongle), troubleshooting — in [`scripts/hotspot/README.md`](scripts/hotspot/README.md).

### 🖥️ Display projection & casting

Two new Settings panes:

- **Projection** (Hyprland) — Windows-style *PC screen only*, *Duplicate*, *Extend* and *Second screen only* for wired monitors, with placement, per-display format and automatic restore when a cable is plugged in. No extra setup: it uses Hyprland's native `mirror` rule and the existing `monitors.lua`.
- **Cast** — set up, discover, connect and configure casting the desktop to a TV. **Local** uses Miracast over Wi‑Fi Direct (waycast, mirror or extend, audio); **LAN & Tailscale** uses DLNA/Cast by address (fluxcast). Miracast is Wi‑Fi Direct P2P and negotiated at up to 1080p, so it cannot traverse a VPN — use the remote mode for a TV on another network.

The Cast helper needs one-time provisioning:

```bash
cd ~/.config/quickshell/end4-pC/optional/cast
./install-user.sh --check            # readiness report
./install-user.sh --install-backends # install helper + waycast + fluxcast into ~/.local
```

Both backends are optional. With them installed, the Cast pane scans Miracast
devices over Wi‑Fi Direct (e.g. a Sony Bravia) and Google Cast/DLNA devices on
the LAN (e.g. an Android TV). The device list has a one-click **Connect**;
stream quality (720p/20 fps by default) is configurable in the same pane.

The installer prints the optional `sudo` steps for the Wi‑Fi Direct supplicant config and firewall port; it never runs them for you. Full guide in [`optional/cast/README.md`](optional/cast/README.md).

### 🎨 Keyboard RGB (colour from Settings)

The Settings → Keyboard colour palette, brightness slider and *Match the
wallpaper colour* need one-time system provisioning (root helper, sudoers rule,
boot-restore unit): the `qc71_laptop` driver never registers a lightbar LED on
this BIOS, so no LED-based app can reach the keyboard. After installing, run:

```bash
cd ~/.config/quickshell/end4-pC/scripts/keyboard-rgb
sudo ./setup-keyboard-rgb.sh     # install (idempotent)  ·  ./setup-keyboard-rgb.sh --check  ·  --uninstall
```

Full guide — the EC register map, why every other path fails on this machine,
the hardware limits, troubleshooting — in
[`scripts/keyboard-rgb/README.md`](scripts/keyboard-rgb/README.md).

### 🔧 Set as your default shell (optional)

If you like it and want it to load by default instead of `ii`, edit:

```bash
~/.config/hypr/hyprland/variables.lua
```

And change this line:

```lua
hl.env("qsConfig", "ii")
```

to:

```lua
hl.env("qsConfig", "end4-pC")
```

> [!TIP]
> After saving, restart Hyprland or run `hyprctl reload` to apply the change.

---

### ⚙️ Settings keybind

To open the settings panel, add this to your Hyprland config:

```lua
hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})
```

> **Note:** Settings is an overlay panel, not a regular window — `Super + Q` won't close it. Use the same keybind to toggle it or press `Escape`.

---

### 📋 Advanced Paste

Copy any text, then press the Advanced Paste shortcut. A popup appears near the cursor with the **detected format** (JSON, Markdown, URL, code, CSV, …) and a list of paste-as transforms:

- **Plain text** — strip Markdown/HTML formatting
- **Markdown** — convert HTML to Markdown, or tidy existing Markdown
- **JSON (pretty)** — pretty-print valid JSON
- **JSON string** — escape arbitrary text into a JSON string literal
- **Code block** — wrap in triple backticks with the detected language
- **Shell quote** — escape for the shell
- **UPPERCASE / lowercase / Title Case**
- **AI transform** — run your own prompt through the configured AI model (falls back to an offline transform when no API key is set).

Select with the number keys or arrow keys, press `Enter` to paste the result into the focused app, `Esc` to cancel. Everything except the optional AI option runs fully offline.

Add this to `~/.config/hypr/custom/keybinds.lua` (or your own keybind file) to bind `Super + Shift + V`:

```lua
hl.bind("SUPER + SHIFT + V", hl.dsp.global("quickshell:advancedPaste"), {description = "Utilities: Advanced Paste"})
```

You can also trigger it from a terminal with `qs ipc call advancedPaste toggle`. Settings for the feature live in Settings → **Tools → Advanced Paste**.

### 🖼️ Image Preview

Press **Super+Shift+I** to view a screenshot from the clipboard, or an image
file. When the clipboard holds a path instead of pixel data it is opened
directly; otherwise a file picker appears. The overlay follows the theme
(Material 3 card, rounded corners) and supports fit/zoom controls and
`Escape`, `+`, `-`, `0` keys.

From a terminal: `qs ipc call imagePreview toggle`, or
`qs ipc call imagePreview openPath /path/to/image.png`. In fish, `img` shows an
image inline (kitty graphics, or a chafa fallback outside kitty), and
`ishow --widget <path>` sends it to the shell widget. In nvim, `<leader>i`
hovers an image reference, `<leader>I` opens an image path, and `:ImagePreview
<path>` previews any readable file.

Companion snippets live in `features/image-preview/`; the QML service is in
`services/ImagePreview.qml` and the panel in `modules/ii/imagePreview/`.

### 🪟 App window theming

External GTK and Qt/KDE applications follow the shell's light/dark mode and
Material You palette. Thunar (GTK3) and Dolphin (Qt/KDE) get MD3 styling from
the same palette the shell uses. The layer is driven by `switchwall.sh` on
every mode change and refreshed by `applycolor.sh` when the palette changes.

**Qt/KDE apps** follow the mode through three knobs the installer sets up:
`QT_STYLE_OVERRIDE=kvantum` in `~/.config/hypr/hyprland/env.lua`, Kvantum's
`theme=MaterialAdw` (light/dark driven by `materialQT.sh`), and qt6ct's
`color_scheme=matugen` (the palette matugen regenerates on every change).
Because Hyprland reads `env.lua` at session start, **log out and back in once**
after installing for Qt apps to pick up the style override. Some apps (GTK3
in particular) only read their CSS at startup — restart them if a change does
not show up immediately.

Configure it under **Settings → Appearance → App theming**: a master switch,
GTK / Qt toggles, a "Manage Qt style" toggle (Kvantum + qt6ct), per-app toggles
for Thunar and Dolphin, and a live-refresh option. See
`features/app-theming/README.md` for the config keys and how to add a sink.
Toggles take effect on the next mode/palette change.

The installer applies the current mode once at install time. To skip parts,
pass `--no-app-theming` (`APP_THEMING=0`), `--no-app-theming-qt-env`
(`APP_THEMING_QT_ENV=0`), or `--no-app-theming-hook`
(`APP_THEMING_MATUGEN_HOOK=0`). The matugen post-hook re-injects the MD3 CSS
block after every palette regeneration, so it cannot be lost.

### 🛠️ Desktop utilities

The same keybind snippet also installs three small PowerToys-style shortcuts:

- `Super + Shift + F` — **Find My Mouse**: highlights the pointer with animated rings for a couple of seconds.
- `Super + Shift + U` — **Screen Ruler**: a draggable, resizable strip showing pixels and centimetres (`Esc` closes it).
- **Keep Awake** (Caffeine) is the existing `Idle` service — toggle it from the quick toggles, or with `qs -c end4-pC ipc call awake toggle`.
- **Always On Top** is Hyprland's window pin (`Super + P` by default), also available as `qs -c end4-pC ipc call utilities alwaysOnTop`.

Extras: OCR from the screen-snip tool now feeds directly into Advanced Paste (toggle in its settings), and the color picker offers HEX / RGB / CSS rgba() / HSL / Flutter formats in the same popup.

---

## ❓ FAQ

### How do I see my keybinds?

Open the launcher (`SUPER`) and type `<` — it'll show you the full list of configured keybinds.

### How do I move a window to another workspace?

- `SUPER + ALT + <1-0>` sends the focused window to workspace N and leaves you on the current one.
- `SUPER + SHIFT + <1-0>` sends it there **and switches to that workspace**. This bind is installed by default into `~/.config/hypr/custom/keybinds.lua`.

### How do I get rid of the close / maximize / minimize buttons?

Hyprland does not draw titlebars at all — the buttons belong to the app's own
toolkit, so there is no `hyprland.conf` option for them. `install.sh` turns them
off by default; to do it by hand:

```bash
# GTK 3/4 apps: no buttons, titlebar stays (apps must be restarted)
for f in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
    sed -i 's|^gtk-decoration-layout=.*|gtk-decoration-layout=:|' "$f"
    grep -q '^gtk-decoration-layout=' "$f" || echo 'gtk-decoration-layout=:' >> "$f"
done
# GNOME/Electron consumers of the same setting
gsettings set org.gnome.desktop.wm.preferences button-layout ':'
# Qt on Wayland: no titlebar/buttons at all (put it in hyprland/env.lua)
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
```

GTK only removes the buttons; the headerbar itself is app UI and stays.
Run the installer with `--keep-window-buttons` (or `DISABLE_WINDOW_BUTTONS=0`)
to leave everything untouched.

### Where are the shell's own window controls?

Since native buttons are off by default, end4-pC provides a four-button
cluster (minimize, maximize/restore, close, and a window-type selector) as a
**bar widget**. Add **Window Controls** to any bar layout from
Settings → Bar → Bar layout; it is in the default left group. It always acts
on the focused window. The type button cycles the focused window between
floating and tiling, switches the session between tiling and stacking, and can
stretch an app over every monitor (span). Button visibility and size are under
`windows.controls` and in Settings (search for "Window controls").

Minimize is a real hide: the window is tagged and parked on the
`special:minimized` workspace, so it disappears from the current workspace but
stays in the dock and in alt-tab. Clicking it in either place activates it and
the shell automatically moves it back to the workspace it came from. No window
is ever closed by the minimize button.

The same actions are available over IPC with `qs -c end4-pC ipc call
windowControls <close|maximize|minimize|restore|setType|cycleType|status>`.
Scripts can target a specific window with `minimizeAddress` / `restoreAddress`.

### Why doesn't Settings have a search bar?

It doesn't need one — the launcher already does that job. Open the launcher (`SUPER`) and just type what you're looking for (e.g. `wallpaper`, `bar`, `blur`); it'll match against page names and section keywords and jump you straight to the right Settings page, so there's no need for a separate search inside Settings itself.

---

## 🙏 Credits

Huge thanks to the people who made this possible:

- **[@end-4](https://github.com/end-4)** — for creating the original [dots-hyprland](https://github.com/end-4/dots-hyprland) / illogical-impulse shell. An absolute masterpiece of a dotfiles project 🫡
- **[@gh0stzk](https://github.com/gh0stzk)** — for providing the weather API integration that made the weather widget possible 🙌
- **[@StarS2112](https://github.com/StarS2112)** — for showcasing this fork 🙌
- **[@simeulinuxkaliaiwr](https://github.com/simeulinuxkaliaiwr)** — for some shader transitions 🎨

---

<div align="center">

Made with ❤️ — feel free to fork and make it your own

</div>
