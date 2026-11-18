



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
