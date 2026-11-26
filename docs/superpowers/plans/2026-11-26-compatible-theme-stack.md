# Compatible Theme Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GTK, QtWidgets and Qt Quick/Kirigami app windows follow end4-pC's light/dark mode and matugen palette, installing compatible themes when possible and generating sleek fallbacks when not.

**Architecture:** Extend the existing app-theming layer rather than replacing it. A new provisioner detects installed themes, optionally installs compatible ones, and writes a resolved map; `app-theming.sh` and `materialQT.sh` consume that map instead of hardcoded theme names; a Qt Quick sink delivers `QT_QUICK_CONTROLS_CONF`/style/mode to native KDE Connect via `env.lua` and an `environment.d` drop-in; a Thunar CSS fix removes toolbar/pathbar borders.

**Tech Stack:** Bash + coreutils + jq, Python 3, Qt Quick Controls 2 config, Hyprland `env.lua`, systemd user `environment.d`, pacman/yay.

**Spec:** `docs/superpowers/specs/2026-11-26-compatible-theme-stack-design.md`

## Global Constraints

- Resolve script paths relative to themselves; never hardcode the deploy directory.
- No new hard dependencies (bash, coreutils, jq, Python, yay/pacman already used).
- Never overwrite GTK CSS wholesale — only replace between `/* end4-pC MD3 app theming:begin */` and `/* end4-pC MD3 app theming:end */`; preserve `gtk-decoration-layout` and all user CSS outside the guard.
- Keep opt-outs working: `APP_THEMING`, `APP_THEMING_QT_ENV`, `APP_THEMING_MATUGEN_HOOK`; add `APP_THEME_PACKAGES`.
- QuickShell cannot inject into third-party windows — config and environment only.
- KDE scheme name is `Matugen` everywhere, never `MaterialYouLight`/`MaterialYouDark`.
- Mode values are literal `light`/`dark`; `QT_QUICK_CONTROLS_MATERIAL_THEME` takes `Light`/`Dark`.
- Package installation runs only from `install.sh` and an explicit "Re-detect" action — never from `switchwall.sh` or `applycolor.sh`.

## Review Focus

- **KDE Connect started as a systemd user service misses Hyprland `env.lua`** → Task 7 asserts an `environment.d` drop-in is written and `systemctl --user import-environment` is invoked.
- **`qtquickcontrols2.conf` is ignored because `QT_QUICK_CONTROLS_CONF` is unset** → Task 4 asserts both the conf bytes and the `QT_QUICK_CONTROLS_CONF` line in `env.lua`.
- **Dolphin regresses when resolved themes replace hardcoded `MaterialAdw`** → Task 5 asserts a resolved `MaterialAdw` produces byte-identical Kvantum config to the old path.
- **Matugen rewrites `gtk.css` and drops the guarded block** → Task 6 asserts the Thunar rules live inside the guard and a second apply is byte-identical.
- **A user's deliberately chosen theme outside the allowlist is overwritten** → Task 2 asserts precedence preserves it.

---

### Task 1: Manifest becomes the window-type catalog

**Files:**
- Modify: `features/app-theming/manifest.json`
- Modify: `docs/design/app-theming.md`
- Test: `tests/app-theming/test_manifest.sh` (new)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: catalog fields `sinks[].id`, `sinks[].toolkit`, `sinks[].applies-to`, `sinks[].config`; new top-level `catalog` array with entries `{id, toolkit, mechanism, compatible: [names], patterns: [globs], fallback}`. Sink ids `qt-quick`, `theme-provision` are reserved for later tasks. Scheme names normalized to `Matugen`.

- [ ] **Step 1: Write the failing test** — `tests/app-theming/test_manifest.sh` asserts `jq -e . features/app-theming/manifest.json` parses, that no string in the manifest matches `MaterialYou`, that `catalog` entries exist for ids `gtk3`, `qtWidgets`, `qtQuick`, and that each has `mechanism`, `compatible`, `patterns`, `fallback` non-empty.
- [ ] **Step 2: Run it** — `bash tests/app-theming/test_manifest.sh`; expected FAIL (missing `catalog`, stale scheme names).
- [ ] **Step 3: Update the manifest** — add the `catalog` array with the four window types from the spec; add `qt-quick` and `theme-provision` sink entries; replace every `MaterialYouLight`/`MaterialYouDark` with `Matugen`. Fix the same stale names in `docs/design/app-theming.md`.
- [ ] **Step 4: Run the test** — expected PASS.
- [ ] **Step 5: Commit** — `git add features/app-theming/manifest.json docs/design/app-theming.md tests/app-theming/test_manifest.sh && git commit -m "feat(app-theming): manifest becomes window-type catalog"`

---

### Task 2: Provisioner detect + resolved map

**Files:**
- Create: `scripts/theming/theme-provision.sh`
- Test: `tests/app-theming/test_theme_provision.sh` (new)

**Interfaces:**
- Consumes: catalog from Task 1.
- Produces: `scripts/theming/theme-provision.sh <light|dark> [--detect|--install|--refresh|--status]`; writes `$XDG_STATE_HOME/quickshell/theme-stack/resolved.json` with shape:
  `{"version":1,"mode":"dark","gtkTheme":"adw-gtk3-dark","kvantumTheme":"MaterialAdw","kvantumSourceDir":"Colloid","kvantumLightSource":"Colloid.kvconfig","kvantumDarkSource":"ColloidDark.kvconfig","qtQuickStyle":"Material","sources":{"gtk":"installed","kvantum":"installed","qtQuick":"builtin"}}`.
  Env seam `APP_THEMING_RESOLVED_FILE` overrides the output path. Consumers read values with `jq -r '.<key> // empty'`.

- [ ] **Step 1: Write the failing test** — fake `$HOME` with: a GTK theme dir `adw-gtk3`, a Kvantum `Colloid` dir with `Colloid.kvconfig`/`ColloidDark.kvconfig`, and a pre-existing `~/.config/Kvantum/kvantum.kvconfig` containing `theme=CustomUserTheme`. Assert `--detect` resolves `gtkTheme=adw-gtk3-dark` in dark mode, `kvantumSourceDir=Colloid`, `qtQuickStyle=Material`, and **preserves** `theme=CustomUserTheme` (Review Focus #5). Add a second case with no theme dirs asserting fallback values `Adwaita-dark`, `MaterialAdw`, `Material`.
- [ ] **Step 2: Run it** — expected FAIL (script missing).
- [ ] **Step 3: Implement the script** — probe theme dirs, score names against the catalog patterns, choose the highest match, keep any valid non-default user theme, and write the JSON atomically via `mktemp` + `mv`. `--install` and `--refresh` may be stubs that call `--detect` for now; `--status` prints the resolved map.
- [ ] **Step 4: Run the test** — expected PASS.
- [ ] **Step 5: Commit** — `git add scripts/theming/theme-provision.sh tests/app-theming/test_theme_provision.sh && git commit -m "feat(app-theming): theme provisioner detect and resolved map"`

---

### Task 3: Provisioner install + installer opt-out

**Files:**
- Modify: `scripts/theming/theme-provision.sh`
- Modify: `install.sh` (usage lines 58–70, parse lines 129–133, validation 143–145, new call beside `apply_app_theming()` at 573), `install-system.sh` (AUR list ~119)
- Test: `tests/app-theming/test_theme_provision.sh` (extend)

**Interfaces:**
- Consumes: `--detect` from Task 2.
- Produces: `--install` adds missing compatible packages to `install-system.sh`'s `aur_pkgs` list by exact name (determine names via `yay -Ss` / AUR search at implementation time and record them in the manifest catalog), best-effort and non-fatal. New flags `--no-theme-packages` / `APP_THEME_PACKAGES=0`; installer calls `theme-provision.sh --install` before `apply_app_theming()`.

- [ ] **Step 1: Extend the test** — assert `--no-theme-packages` sets `APP_THEME_PACKAGES=0` in `install.sh`, that `install.sh --help` documents the flag, and that an invalid `--theme-packages=bogus` exits 2 without writes (mirror existing invalid-option tests). Assert `--install` is safe with `APP_THEMING_NO_EXTERNAL=1` (no package manager calls).
- [ ] **Step 2: Run it** — expected FAIL.
- [ ] **Step 3: Implement** — add flag parsing/validation/help/usage, call the provisioner from the install flow gated by `APP_THEME_PACKAGES`, add verified AUR package names to `aur_pkgs`, and make `--install` a no-op under `APP_THEMING_NO_EXTERNAL=1`.
- [ ] **Step 4: Run the test and `bash -n install.sh install-system.sh scripts/theming/theme-provision.sh`** — expected PASS.
- [ ] **Step 5: Commit** — `git add install.sh install-system.sh scripts/theming/theme-provision.sh tests/app-theming/test_theme_provision.sh && git commit -m "feat(install): provision compatible themes with opt-out"`

---

### Task 4: Qt Quick sink + resolved-map consumption in app-theming.sh

**Files:**
- Modify: `scripts/theming/app-theming.sh`
- Create: `features/app-theming/qtquickcontrols2.conf.tmpl`
- Test: `tests/app-theming/test_app_theming.sh` (extend)

**Interfaces:**
- Consumes: resolved map from Task 2 (`APP_THEMING_RESOLVED_FILE` seam).
- Produces: `apply_qtquick()` gated by `.appearance.appTheming.qtQuick` (default true), writing `$XDG_CONFIG_HOME/qtquickcontrols2.conf` and adding `QT_QUICK_CONTROLS_CONF`, `QT_QUICK_CONTROLS_STYLE`, `QT_QPA_PLATFORMTHEME` lines to `hyprland/env.lua`. New config keys `qtQuick`, `provision`, `preferredFamily` read via the existing `cfg`/`enabled` helpers.

- [ ] **Step 1: Extend the test** — after a dark apply assert: `$XDG_CONFIG_HOME/qtquickcontrols2.conf` contains `Theme=Dark` and `Accent=ff0000`; `env.lua` contains `QT_QUICK_CONTROLS_CONF`, `QT_QUICK_CONTROLS_STYLE=Material`, `QT_QPA_PLATFORMTHEME=qt6ct`; and the guarded CSS is still byte-identical on a second apply (Review Focus #4). Add a case with `.appearance.appTheming.qtQuick=false` asserting no conf file is written.
- [ ] **Step 2: Run it** — expected FAIL.
- [ ] **Step 3: Implement** — add template rendering through the existing `render_template` path, a `write_config_file` helper for the standalone conf, and `set_lua_env` (sed-based, idempotent) for `env.lua`. Gate GTK name and Kvantum name on resolved values with defaults `adw-gtk3`/`adw-gtk3-dark` and `MaterialAdw`.
- [ ] **Step 4: Run the test** — expected PASS.
- [ ] **Step 5: Commit** — `git add scripts/theming/app-theming.sh features/app-theming/qtquickcontrols2.conf.tmpl tests/app-theming/test_app_theming.sh && git commit -m "feat(app-theming): Qt Quick sink and resolved theme names"`

---

### Task 5: Kvantum theme roles come from the resolved map

**Files:**
- Modify: `scripts/kvantum/materialQT.sh`
- Test: `tests/app-theming/test_kvantum_roles.sh` (new)

**Interfaces:**
- Consumes: `kvantumTheme`, `kvantumSourceDir`, `kvantumLightSource`, `kvantumDarkSource` from Task 2; same `APP_THEMING_RESOLVED_FILE` seam.
- Produces: no signature change to callers; `materialQT.sh` still invoked as `bash "$MATERIAL_QT"` from `app-theming.sh`.

- [ ] **Step 1: Write the failing test** — fake `$HOME` with `~/.config/Kvantum/Colloid/Colloid.kvconfig` and `ColloidDark.kvconfig`; resolved map pointing theme `MaterialAdw`, source dir `Colloid`. Assert dark apply copies `ColloidDark.kvconfig` to `~/.config/Kvantum/MaterialAdw/MaterialAdw.kvconfig` and light apply copies `Colloid.kvconfig` (Review Focus #3: byte-identical to the old behavior). Assert a missing source dir does NOT call `notify-send` when `APP_THEMING_NO_EXTERNAL=1`.
- [ ] **Step 2: Run it** — expected FAIL (script hardcodes paths).
- [ ] **Step 3: Implement** — read resolved values with `jq`, build source/destination paths from them, keep the existing `get_light_dark()` behavior and `adwsvg*.py` calls, and guard `notify-send` behind `APP_THEMING_NO_EXTERNAL != 1`.
- [ ] **Step 4: Run the test** — expected PASS.
- [ ] **Step 5: Commit** — `git add scripts/kvantum/materialQT.sh tests/app-theming/test_kvantum_roles.sh && git commit -m "feat(kvantum): drive theme roles from resolved map"`

---

### Task 6: Thunar toolbar/pathbar borders

**Files:**
- Modify: `features/app-theming/gtk3.css.tmpl`
- Test: `tests/app-theming/test_app_theming.sh` (extend)

**Interfaces:**
- Consumes: palette tokens already rendered by `render_template`.
- Produces: CSS rules only, no new tokens.

- [ ] **Step 1: Extend the test** — assert the generated GTK3 CSS contains Thunar-scoped selectors setting `border: none` / `box-shadow: none` on toolbar, path bar and linked entries, and that every new rule sits between the guard markers (Review Focus #4).
- [ ] **Step 2: Run it** — expected FAIL.
- [ ] **Step 3: Implement** — add Thunar-focused selectors after the existing Thunar block using `@md3_surface_container`, `border: none`, `box-shadow: none`, and the shell's radius tokens expressed as literal `12px`/`8px` (CSS cannot read QML tokens). Do not touch rules outside the guard.
- [ ] **Step 4: Run the full app-theming test** — expected PASS including idempotency.
- [ ] **Step 5: Commit** — `git add features/app-theming/gtk3.css.tmpl tests/app-theming/test_app_theming.sh && git commit -m "fix(thunar): borderless MD3 toolbar and path bar"`

---

### Task 7: Mode delivery to native KDE Connect

**Files:**
- Modify: `scripts/theming/app-theming.sh` (`signal_apps()`), `install.sh` (`apply_qt_style_env()`), `install-system.sh` or new `systemd/user/` drop-in source
- Test: `tests/app-theming/test_app_theming.sh` (extend)

**Interfaces:**
- Consumes: `QT_QUICK_CONTROLS_CONF` line from Task 4.
- Produces: an `environment.d` drop-in at `$XDG_CONFIG_HOME/environment.d/90-end4-pc-app-theming.conf` containing `QT_QPA_PLATFORMTHEME=qt6ct`, `QT_QUICK_CONTROLS_STYLE=Material`, `QT_QUICK_CONTROLS_CONF=<path>`, `QT_QUICK_CONTROLS_MATERIAL_THEME=<Light|Dark>`; rewritten per mode by `app-theming.sh`. `signal_apps()` calls `systemctl --user import-environment` and best-effort restarts KDE Connect when `refreshRunningApps` is true.

- [ ] **Step 1: Extend the test** — under `APP_THEMING_NO_EXTERNAL=1` assert: dark apply writes `QT_QUICK_CONTROLS_MATERIAL_THEME=Light`? No — assert exactly `Dark` for dark mode and `Light` for light mode; assert the drop-in is rewritten on a mode switch (not duplicated); assert `env.lua` is not given duplicate keys after two applies (Review Focus #1).
- [ ] **Step 2: Run it** — expected FAIL.
- [ ] **Step 3: Implement** — add `write_environment_dropin()` and `set_lua_env()` calls in `apply_qtquick()`/mode path; extend `signal_apps()` with `systemctl --user import-environment` and `pkill kdeconnect-app`/`kdeconnectd` (best-effort, only when `NO_EXTERNAL != 1`).
- [ ] **Step 4: Run the test** — expected PASS.
- [ ] **Step 5: Commit** — `git add scripts/theming/app-theming.sh install.sh tests/app-theming/test_app_theming.sh && git commit -m "feat(kde-connect): deliver Qt Quick mode to systemd children"`

---

### Task 8: Settings keys, toggles and Re-detect action

**Files:**
- Modify: `modules/common/Config.qml` (after line 194), `modules/ii/settings/DashboardSettingsCatalog.qml` (override map ~207–213, cards ~700–708)
- Test: `tests/qml-compile-check.sh`, `tests/functional-coverage.sh`

**Interfaces:**
- Consumes: script config keys from Tasks 2/4 (`qtQuick`, `provision`, `preferredFamily`).
- Produces: QML properties `appearance.appTheming.qtQuick`, `.provision`, `.preferredFamily`; settings keys `interface:Theme Qt Quick apps`, `interface:Auto-install themes`, `interface:Preferred theme family`, and action `interface:Re-detect themes` that runs `theme-provision.sh --install --refresh` via `Quickshell.execDetached`.

- [ ] **Step 1: Add the settings entries and a failing coverage assertion** — register the four keys in `DashboardSettingsCatalog.qml` using the existing override-map pattern; add a check to `tests/functional-coverage.sh` (or its mapping file) that the new keys are mapped. Run it; expected FAIL.
- [ ] **Step 2: Implement** — add the QML properties with defaults (`qtQuick: true`, `provision: true`, `preferredFamily: "auto"`), wire the switches to `applyAppTheming()`, and add the action entry.
- [ ] **Step 3: Run `bash tests/qml-compile-check.sh` and `bash tests/functional-coverage.sh`** — expected PASS.
- [ ] **Step 4: Commit** — `git add modules/common/Config.qml modules/ii/settings/DashboardSettingsCatalog.qml tests/ && git commit -m "feat(settings): expose theme stack controls"`

---

### Task 9: Docs and end-to-end verification

**Files:**
- Modify: `README.md`, `features/app-theming/README.md`
- Create: `docs/design/theme-stack.md`
- Test: `tests/app-theming/test_app_theming.sh`, `tests/app-theming/test_theme_provision.sh`, `tests/app-theming/test_kvantum_roles.sh`, `tests/app-theming/test_manifest.sh`, `bash -n` on changed scripts, `sync.sh --check`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: documentation only.

- [ ] **Step 1: Document** — add a "Compatible theme stack" section to `README.md` and `features/app-theming/README.md` covering the window-type table, new opt-outs, the re-login requirement, and the KDE Connect restart behavior; copy the approved design into `docs/design/theme-stack.md`.
- [ ] **Step 2: Run all four app-theming tests plus `bash -n` on every changed script** — expected all PASS.
- [ ] **Step 3: Run `bash tests/qml-compile-check.sh` and `./sync.sh --check`** — expected PASS/clean.
- [ ] **Step 4: Manual smoke (user-visible)** — toggle light/dark and confirm KDE Connect follows, Dolphin unchanged, Thunar borders gone. If Kirigami still overrides the style, report it as an escalation rather than adding another layer of workarounds.
- [ ] **Step 5: Commit** — `git add README.md features/app-theming/README.md docs/design/theme-stack.md && git commit -m "docs: document compatible theme stack"`

---

## Self-review notes

- Spec sections mapped: intent → Task 9 docs; goals → Tasks 2–7; non-goals → Global Constraints; window-type catalog → Task 1; provisioner → Tasks 2–3; Qt Quick sink → Task 4 + 7; QtWidgets → Task 5; GTK/Thunar → Task 6; settings → Task 8; verification → Task 9.
- Review Focus items each have a test in the owning task (#1 Task 7, #2 Task 4, #3 Task 5, #4 Task 6, #5 Task 2).
