# Design: compatible theme stack for all window types

**Status:** approved (2026-11-26) · **Scope:** GTK / QtWidgets / Qt Quick–Kirigami application windows

## Intent and why

end4-pC already derives a Material You palette from the wallpaper and follows a
light/dark mode. An earlier layer (`features/app-theming/`,
`scripts/theming/app-theming.sh`) pushes that mode and palette to external GTK
and Qt/KDE apps, but it is fragile:

- `install-system.sh` installs **no** app-theme packages. The layer assumes
  `adw-gtk3`, Kvantum, and `qt6ct` already exist.
- `scripts/kvantum/materialQT.sh` hard-depends on an externally-installed
  Kvantum **Colloid** theme at `~/.config/Kvantum/Colloid/` and exits with a
  notification when it is absent.
- There is no Qt Quick / Kirigami sink at all, so KDE Connect stays stock.

## Verification that grounded this design (user, 2026-11-26)

- **KDE Connect** is stuck in light theme although the system is in dark mode.
- **Dolphin** is already correct — styles follow the installed theme.
- **Thunar** shows unwanted borders on its toolbar/path bar ("bar design borders").
- Live system check: native `kdeconnect-app`, `kdeconnect-cli`, `kdeconnectd`
  exist (no Flatpak install); `gsettings color-scheme = prefer-dark`;
  `kdeglobals ColorScheme = Matugen`; `gtk-theme = adw-gtk3-dark`.

So this is a targeted extension, not a rewrite: keep the working Dolphin path,
add explicit Qt Quick mode/palette delivery, and fix the Thunar CSS.

## Goals

- Every window type follows the shell's light/dark mode and matugen palette.
- The closest compatible Material-like theme is used when available; missing
  themes are installed at install/re-detect time.
- Minimal, sleek generated styles cover the offline / no-compatible-theme case.
- KDE Connect is explicitly in scope and verified in both modes.
- Thunar's chrome is borderless and MD3-shaped inside the guarded CSS block.

## Non-goals / anti-goals

- Electron, Firefox, LibreOffice, terminal emulators (own theming systems).
- Owning the user's base GTK theme or CSS files.
- Forcing GTK4/libadwaita apps that ignore external CSS (best-effort only).
- Guaranteeing live reload for every app — some toolkits need a restart.
- Installing packages on every wallpaper/mode switch.

## Constraints

- Scripts resolve paths relative to themselves; never hardcode the deploy dir.
- No new hard dependencies: bash + coreutils + jq + Python + yay/pacman.
- GTK CSS is never overwritten wholesale — only the guarded block
  `/* end4-pC MD3 app theming:begin|end */` is replaced; `gtk-decoration-layout`
  and all text outside the guard survive.
- Existing opt-outs keep working: `APP_THEMING`, `APP_THEMING_QT_ENV`,
  `APP_THEMING_MATUGEN_HOOK`, plus the new `APP_THEME_PACKAGES`.
- QuickShell cannot inject into third-party windows — config/env only.
- The generated KDE scheme name is `Matugen` everywhere (never
  `MaterialYouLight`/`MaterialYouDark`).
- Mode values are literal `light`/`dark`; `QT_QUICK_CONTROLS_MATERIAL_THEME`
  takes `Light`/`Dark`.

## Approaches considered

1. **Provision + detect + fallback (chosen).** Install compatible themes, detect
   and use the closest one, generate a sleek fallback when none exists. Only
   option that satisfies "right themes installed" and covers KDE Connect.
2. **Self-contained generated theme.** Lower fidelity, reinvents Kvantum SVG,
   ignores compatible themes that are already installed — rejected.
3. **Detection only.** A fresh system stays stock — rejected.

## Window-type catalog

| Type | Apps | Mechanism | Compatible theme | Fallback |
|---|---|---|---|---|
| GTK 2/3 | Thunar, Nautilus, most GNOME apps | `gtk-theme-name`, dark pref, guarded CSS | `adw-gtk3` / `adw-gtk3-dark` | Adwaita + guarded MD3 CSS |
| GTK 4/libadwaita | some GNOME apps | gsettings dark pref; CSS where honored | best-effort | gsettings mode only |
| QtWidgets | Dolphin, Kate, qBittorrent | `QT_STYLE_OVERRIDE`, Kvantum, qt6ct, KDE `ColorScheme` | Kvantum `Colloid`/`MaterialAdw` | Fusion + qt6ct `matugen` palette |
| Qt Quick/Kirigami | **KDE Connect**, EasyEffects ≥8 | QQC2 style/config + KDE ColorScheme | built-in `Material` style | same (no package needed) |

The catalog lives in the existing `features/app-theming/manifest.json`, which
becomes the single source of truth (no competing `catalog.json`).

## Design details

### A. Provisioner — `scripts/theming/theme-provision.sh`

New script with `--detect`, `--install`, `--refresh`, `--status`:

- Filesystem probes for installed themes (GTK theme dirs, Kvantum theme dirs,
  qt6ct presence).
- Score candidates against allowlist patterns: `MaterialAdw`, `Colloid`,
  `Material*`, `Adw*`, `md3*`.
- Write a resolved map to
  `$XDG_STATE_HOME/quickshell/theme-stack/resolved.json` using the same
  `APP_THEMING_*` env seams as existing scripts.
- `--install` installs missing compatible themes via yay/pacman, best-effort and
  non-fatal. Runs **only** from `install.sh` and from an explicit "Re-detect"
  action — never from `switchwall.sh`.
- Precedence: keep a valid user-selected theme; only override when missing or
  default. A user's deliberate theme choice is not stomped. *(Design call.)*
- Delivery to non-Hyprland children: also write an `environment.d` drop-in and
  call `systemctl --user import-environment`; best-effort `flatpak override`
  for Flatpak targets (KDE Connect here is native, so that path is secondary).

### B. Qt Quick / KDE Connect mode sink

- Generate `~/.config/qtquickcontrols2.conf` from a template with
  `[Material] Theme=Dark|Light` and `Accent=<matugen primary hex>`.
- Qt only reads this file from `:/qtquickcontrols2.conf` or the path in
  `QT_QUICK_CONTROLS_CONF`, so set `QT_QUICK_CONTROLS_CONF=<path>` explicitly.
- Also set `QT_QUICK_CONTROLS_STYLE=Material` and
  `QT_QUICK_CONTROLS_MATERIAL_THEME=<Dark|Light>` in `hyprland/env.lua` **and**
  the `environment.d` drop-in, so a systemd-started `kdeconnectd` receives them.
- Kirigami palette comes from the already-set `Matugen` KDE ColorScheme.
- On mode change, best-effort restart of KDE Connect behind the existing
  `refreshRunningApps` toggle (Kirigami may cache the palette at startup).
- The shell's own `//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic` is unaffected.

### C. QtWidgets — keep Dolphin working

- `materialQT.sh` maps both roles from the resolved map: the light/dark **source**
  kvconfigs and the **destination** theme folder. Today both are hardcoded to
  Colloid → MaterialAdw.
- `app-theming.sh` stops hardcoding `theme=MaterialAdw`; the value comes from the
  resolved map. On a system with MaterialAdw present the result must be identical.
- The Fusion fallback additionally needs `QT_QPA_PLATFORMTHEME=qt6ct` in
  `env.lua` (currently only the render test sets it), otherwise qt6ct's palette
  never reaches Qt apps.

### D. GTK / Thunar

- Keep the guarded CSS block and `adw-gtk3` / `adw-gtk3-dark`.
- Add Thunar-scoped rules that remove borders/shadows on the toolbar, path bar
  and linked entries, using `md3_surface_container` surfaces and the existing
  radius ladder. All rules stay inside the guarded block.
- GTK4/libadwaita remains best-effort: mode via gsettings, CSS where honored.

### E. Settings

- New keys under `appearance.appTheming`: `provision` (auto-install),
  `qtQuick` (KDE Connect/Kirigami sink), `preferredFamily`.
- Add toggles and a "Re-detect themes" action in
  `modules/ii/settings/DashboardSettingsCatalog.qml`, following the existing
  override-map pattern at lines 207–213 and cards at 700–708 (an
  `type: "action"` pattern already exists). Status is a simple text/log panel,
  not a new control type.

### F. Tests

- `tests/app-theming/test_theme_provision.sh` — fake `$HOME` with fake theme
  dirs: detection, allowlist scoring, fallback, user-theme precedence.
- Extend `tests/app-theming/test_app_theming.sh` — Qt Quick config/env bytes,
  resolved map consumption, Thunar border rules, guarded-block idempotency.
- Extend the render test for both modes; KDE Connect stays a manual smoke test
  (running the daemon under Xvfb is flaky).
- Installer `--help` / dry-run / invalid-option tests for the new flag.

## Verification

- All app-theming shell tests pass; QML compile check clean; `sync.sh --check`
  clean.
- Manual: toggle light/dark and confirm KDE Connect follows, Dolphin unchanged,
  Thunar borders gone.
- Escalate if Kirigami still overrides the Qt Quick style after env + restart.

## What is left to the builder

Confirm exact AUR package names at implementation time (AUR search), and verify
the Qt Quick config path with a small QQC2 sample under Xvfb before relying on
it in the real app.
