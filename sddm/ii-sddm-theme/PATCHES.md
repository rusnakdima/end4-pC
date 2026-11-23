# Local patches vs upstream `3d3f/ii-sddm-theme`

This directory is vendored from the locally installed greeter at
`/usr/share/sddm/themes/ii-sddm-theme`. It is **not** a pristine upstream copy.
The divergences below are intentional local changes and must survive reinstalls.

| File | Local change | Reason |
| --- | --- | --- |
| `Components/UserButton.qml` | Hardcoded avatar `file:///home/dmitriy/Pictures/ava/ava-violet-2x.png` for the `dmitriy` user | Personalised user tile on this device |
| `Components/Colors.qml` | Custom colour palette | Matches the rest of the desktop theme |
| `Components/Settings.qml` | Generated per-device values | Local greeter settings (kept per device on install) |
| `Themes/ii-sddm.conf` | Generated values, mp4 background/placeholder | Local wallpaper/theme selection (kept per device on install) |
| `iiMatugen/sddm-theme-apply.sh` | Root-aware `run_root` helper | Apply the theme from a root-owned install without breaking permissions |
| `iiMatugen/Settings.qml` | Generated per-device values | Matugen variant settings (kept per device on install) |
| `noMatugen/Settings.qml` | Generated per-device values | Non-matugen variant settings (kept per device on install) |
| `setup.sh` | `sudo -n` for non-interactive setup | Allows the installer to run without prompting for a password |

Other files are upstream-derived. `Backgrounds/background.*` and
`Backgrounds/placeholder.png` are generated wallpaper artifacts and are
deliberately **not** tracked here; `install.sh` syncs them from the user's
current wallpaper.
