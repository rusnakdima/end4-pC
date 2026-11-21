# Design: external app window theming

**Status:** approved (2026-11-21) · **Scope:** GTK + Qt/KDE first

## Intent

The shell already derives a complete Material You palette from the wallpaper
and follows a light/dark mode. External applications did not: GTK and Qt/KDE
windows kept their own theme, so Thunar and Dolphin looked foreign next to the
shell. This feature adds a theme-owned layer that pushes the same mode and
palette to those apps.

## Goals

- Every GTK 2/3/4 and Qt/KDE window follows the shell's light/dark mode.
- Thunar (GTK3) and Dolphin (Qt/KDE) receive MD3 styling from the same palette.
- Reuse existing infrastructure: matugen palette, `adw-gtk3`, Kvantum
  `MaterialAdw`, KDE `MaterialYou*` schemes. No new dependencies.
- Keep user edits to GTK config/CSS intact.

## Non-goals / anti-goals

- Electron, Firefox, LibreOffice and terminal emulators (own theming systems).
- Owning the user's base GTK theme or CSS files.
- Guaranteeing live reload for every app — some toolkits need a restart.

## Constraints

- The repo is a QuickShell config, deployed by `sync.sh` to
  `~/.config/quickshell/end4-pC`; scripts must resolve paths relative to
  themselves, never to a hardcoded config directory.
- Existing scripts read toggles from `~/.config/illogical-impulse/config.json`
  with `jq`; the new layer follows that convention.
- `install.sh` and `sync.sh` carry independent in-progress user edits; changes
  to them must be additive and surgical.

## Approaches considered

1. **Theme-owned layer (chosen).** A dedicated `app-theming.sh` reads the
   palette and applies all sinks. Mode changes call it from `switchwall.sh`;
   palette changes call it from `applycolor.sh`. Central, testable, no new
   dependencies.
2. **Patch each app's config independently.** Scattered edits across many
   files with no single place to test or disable; rejected.
3. **External daemon watching the palette file.** Adds a process and a startup
   dependency for a problem already solved by existing hooks; rejected.

## Design

- **Mode authority:** explicit `<light|dark>` argument from `switchwall.sh`;
  fall back to `gsettings color-scheme`.
- **GTK sink:** set gsettings/`settings.ini` theme + dark preference (preserving
  `gtk-decoration-layout`), then render `gtk3.css.tmpl` / `gtk4.css.tmpl` into
  a block delimited by `/* end4-pC MD3 app theming:begin|end */` in the user's
  `gtk.css`. Only the block is replaced; everything outside is preserved.
- **Qt/KDE sink:** Qt apps only follow the theme when three knobs agree, so the
  script drives all of them (gated by `manageQtStyle`):
  1. `QT_STYLE_OVERRIDE=kvantum` in `~/.config/hypr/hyprland/env.lua` (installer;
     requires re-login — a running Hyprland cannot change its child apps' env),
  2. Kvantum active `theme=MaterialAdw` in `kvantum.kvconfig`, because that is
     the theme `materialQT.sh` writes its light/dark Colloid kvconfig into,
  3. `color_scheme=matugen` in `qt6ct.conf`, the palette matugen regenerates.
  `kdeglobals` gets `ColorScheme=Matugen` (the real generated
  `Matugen.colors` file); nonexistent `MaterialYou*`/`IllogicalNamed*`
  schemes were removed. `plasma-apply-colorscheme` is called only if installed.
- **GTK resilience:** matugen overwrites `gtk.css` on every apply. The guarded
  block is re-injected both by `applycolor.sh --refresh` and by a matugen
  `post_hook` installed for the GTK templates, so a failed hook cannot lose it.
- **Signals:** gsettings/dconf for GTK, `KGlobalSettings.notifyChange` for Qt.
- **Toggles:** `appearance.appTheming.*` in `Config.options`, surfaced in
  Settings → Appearance → App theming and read by the script via `jq`.

## Verification

`tests/app-theming/test_app_theming.sh` runs the script against a throwaway
`$HOME`: both modes, template placeholders, guarded-block preservation,
`gtk-decoration-layout` survival, idempotency, `--refresh`, and the master
toggle. QML compile check and `functional-coverage.sh` guard the wiring.

## What is left to the builder

Manual smoke test: open Thunar and Dolphin, toggle dark mode from the shell,
confirm both follow without a restart where the toolkit supports it.
