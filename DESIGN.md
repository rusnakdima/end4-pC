# DESIGN.md — Window Controls Bar Widget (end4-pC)

Design and implementation artifact for the shell-drawn window controls in end4-pC.

This document describes **design and architecture only**. Implementation lives in the files listed in Appendix A.

---

## 1. Visual Theme & Atmosphere

A compact, confident control cluster that lives in the bar and acts on the focused window. It is system utility, not app UI: Material 3 Expressive surfaces, short motion, no ornament. The three familiar window actions follow Windows behaviour; the fourth button — the window-type control — is the distinctive one.

There is deliberately **no overlay on app windows**. Native titlebars stay untouched. All state and feedback is in the bar and in the compositor.

---

## 2. Color Palette & Roles

Colours resolve at runtime from matugen through `Appearance`; no hex values are hardcoded. Reference hexes are illustrative only.

| Semantic role | QML token | Reference | Use |
|---|---|---|---|
| Surface | `Appearance.colors.colLayer0` / `colSurfaceContainer` | `#1b1b1f` | Cluster and type menu background |
| Primary icon | `Appearance.m3colors.m3onSurface` | `#e3e1e5` | Minimize / maximize / type icons |
| Destructive | `Appearance.colors.colError` / `colOnError` | `#ffb4ab` | Close button |
| Selected type | `Appearance.colors.colPrimary` / `m3onPrimary` | `#c9c2ff` | Active type in the menu |
| Divider / outline | `Appearance.colors.colOutlineVariant` | `#77737e` | Separator before the type button |

---

## 3. Typography Rules

| Role | Font | Size | Notes |
|---|---|---|---|
| Button glyph | Material Symbols Rounded (via `MaterialSymbol`) | `Appearance.font.pixelSize.normal` | `minimize`, `crop_square` / `filter_none`, `close`, `layers` |
| Type-menu title | `Appearance.font.family.title` | `pixelSize.small` | "Window type" |
| Type-menu item | `Appearance.font.family.body` | `pixelSize.normal` | Floating / Tiling / Stacking / Span |

The selected type is shown by a filled chip **and** a checkmark — never by colour alone.

---

## 4. Component Stylings

### 4.1 Bar widget
- Registered as `windowControls` in `DashboardBarWidgets`, so it can be added to any bar layout from Settings → Bar.
- Default: included in the left bar group after `activeWindow`.
- Compact mode, embedded in the bar (no separate pill surface). Buttons 28 dp, radius `Appearance.rounding.full`, 2 dp gap, 6 dp divider before the type button.

### 4.2 Verified glyphs
- The bundled Material Symbols font renders `maximize` as a dash and `restore` as a clock. Use `crop_square` (square) and `filter_none` (two overlapping squares) instead — verified with a rendered icon lab.
- Minimize = `minimize`, close = `close`, type = `layers`.

### 4.3 Window-type menu
- Opened from the fourth button when the widget has room; otherwise the button cycles Floating → Tiling → Stacking → Span with a tooltip.
- 208 dp wide, `colSurfaceContainer`, `Appearance.rounding.normal`, four 36 dp rows.
- Span is labelled "Span (all monitors)" because it is a per-app rule, not a session mode.

### 4.4 States
- Idle: icon at ~0.85 opacity. Hover: `colLayer1Hover`, 120 ms. Pressed: 0.9 scale. Focus: `colPrimary` ring.
- Disabled: 0.4 opacity — no active window, minimized already, maximize on a span window.

---

## 5. Layout Principles

- Spacing base 4 dp; radius ladder `small` → `normal` → `large` → `full`.
- The widget is self-contained and works in left, centre or right bar groups.
- Right-to-left button order is supported by config (`windows.controls.buttons`).

---

## 6. Depth & Elevation

- The bar widget has no elevation of its own; it inherits the bar's surface.
- The type menu uses one elevation level above the bar with a soft drop shadow.
- No full-screen layer surface, no input mask, no z-order management: the overlay approach was removed.

---

## 7. Do's and Don'ts

- DO keep the three window actions behaviourally identical to Windows.
- DO keep minimized windows reachable from the dock and alt-tab, and restore their original workspace.
- DO proxy `WindowMode` for mode changes; never duplicate its rule file.
- DON'T draw a titlebar over app windows.
- DON'T hardcode colours, glyphs or sizes that have an `Appearance` token.

---

## 8. Responsive Behavior

- Multi-monitor: the widget acts on whichever window is focused; no geometry tracking.
- Small bars: icons only, no labels; the type menu is replaced by cycling.
- Fullscreen / span: maximize is disabled for span windows; fullscreen windows are left alone.
- Minimize: works on every Hyprland window because it uses a special workspace, not an app-specific minimize capability.

---

## 9. Agent Prompt Guide

### Quick token reference
```
Cluster surface:  Appearance.colors.colSurfaceContainer
Hover:            Appearance.colors.colLayer1Hover
Primary icon:     Appearance.m3colors.m3onSurface
Close:            Appearance.colors.colError / colOnError
Selected type:    Appearance.colors.colPrimary / m3onPrimary
Outline:          Appearance.colors.colOutlineVariant
Glyphs:           minimize | crop_square | filter_none | close | layers
```

### Example component prompts
- "Build a bar widget with four 28 dp circular icon buttons in a row, `colSurfaceContainer` idle, `colLayer1Hover` on hover, `colPrimary` focus ring, 2 dp gaps, and a 6 dp divider before the last button."
- "Use `minimize` for minimize, `crop_square` for maximize, `filter_none` for restore and `close` for close. Do not use the Material Symbols names `maximize` or `restore`."
- "Build a window-type menu with four rows — Floating, Tiling, Stacking, Span (all monitors) — with the selected row filled with `colPrimary` and a checkmark. Proxy mode changes through the WindowControls service."
- "Implement minimize by tagging the focused window and moving it to `special:minimized` with `follow = false`, recording its original workspace in Persistent. When the dock or alt-tab activates it, move it back and clear the tag."

### Iteration guide
1. All colours, radii and glyph sizes come from `Appearance`.
2. The first three buttons must behave like Windows; the fourth is the only novel control.
3. Minimize never closes a window and never removes it from the dock or alt-tab.
4. `WindowMode` stays the single source of truth for tiling/stacking/span.
5. The bar widget never tracks window geometry and never overlays app content.

---

## Appendix A — Implementation Plan (as built)

### A.1 File inventory
| File | Change |
|---|---|
| `services/WindowControls.qml` | new — actions, dispatchers, demo mode, IPC |
| `modules/common/widgets/WindowControlsCluster.qml` | new — button cluster |
| `modules/common/widgets/WindowTypeMenu.qml` | new — type chooser |
| `modules/ii/bar/WindowControls.qml` | new — bar-layout widget |
| `modules/common/Config.qml` | modify — `windows.controls`, default bar layout |
| `modules/common/Persistent.qml` | modify — minimized-window records |
| `modules/ii/settings/DashboardBarWidgets.qml` | modify — widget registration |
| `modules/ii/settings/DashboardSettingsCatalog.qml` | modify — settings entries |
| `modules/ii/windowSwitcher/WindowSwitcher.qml` | modify — keep minimized clients listed |
| `tests/shell-tests/tst_window_controls.qml` | new — pure-logic tests |
| `tests/shell-tests/shell.qml`, `tests/functional-coverage.sh` | modify — test registration |
| `README.md` | modify — documentation |

### A.2 Minimize design
Hyprland 0.57 has no native minimize dispatcher (`hl.dsp.window.minimize` is nil). The implemented behaviour:
1. Record `{ address, workspace }` in `Persistent.states.windowControls.minimized`.
2. Dispatch `hl.dsp.window.tag({ tag = "minimized", window = "address:..." })`.
3. Dispatch `hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:..." })`.
4. On `activewindow`, if the address is in the record list, move it back to its workspace, clear the tag, remove the record and focus it. This is what makes dock / alt-tab clicks restore the window.

Verified directly with `hyprctl dispatch` on a throwaway window: hide → `special:minimized` with `minimized` tag; restore → original workspace with no tags.

### A.3 Verification
- `tests/qml-compile-check.sh` PASS on all changed QML.
- Hosted shell tests: `tst_window_controls` 19/19; overall suite unchanged from baseline (37 files passed, 6 pre-existing environment failures).
- `tests/functional-coverage.sh`: no new unmapped areas.
- `sync.sh --check`: clean (deployment requires the session to be unlocked).
