# Duplicate settings controls: keep every copy live in sync

> The same setting can be edited from Settings and from another shell surface (right sidebar edit mode, bar popups, wallpaper picker, desktop right-click menus, overview search). After a user touches one of those controls it stops following the config, so the other copy shows a different value for the rest of the session. Keep both entry points and make them a true two-way mirror.

**Status**: Active
**Created**: 2026-11-18
**Owner**: frontend-engineer

## Goal

1. Every settings parameter that has a control in more than one shell surface (Settings pages, Settings dashboard, Settings/overview search, right sidebar, left sidebar, bar widgets/popups, wallpaper picker, desktop context menus, first-run welcome) reflects a change made in any other surface immediately, without reopening the window or reloading the shell.
2. The duplication itself stays: each surface keeps its existing control, wording and layout. Only the data path changes.
3. Add a repeatable guard so a newly duplicated control cannot silently regress, plus a hosted test that proves the two-way path for switches, spin boxes, sliders and combo boxes.
4. Fix the cross-key duplicates that store the same user intent in two config leaves and currently write only one of them.

## Context

### Root cause: the bound property is overwritten by the control itself

Every `Config*` editor binds its user-writable property to the config value and then assigns that same property when the user interacts. In QML an imperative assignment removes the declarative binding, so after the first interaction the control only pushes to the config and never pulls again. Two copies that were both touched then diverge permanently.

- `ConfigSwitch.qml:21-24` — `onClicked: { checked = !checked; root.userToggled(root.checked) }` (working tree already adds `userToggled`; `checked` is still self-assigned).
- `ConfigSpinBox.qml:10,38-39` — `value` is an alias to `StyledSpinBox.value`, and the spin box writes `value` while the user edits it.
- `ConfigSlider.qml:15,47-50` — `value` is an alias to `StyledSlider.value`, same problem.
- `ConfigTextArea.qml:14` — `value` is an alias to `TextArea.text`, which the text editor writes.
- `ConfigComboBox.qml:65-68,85-88` — `currentValue` is only read, but the inner `currentIndex` is computed from it. Selecting an item writes `currentIndex` and kills that computed binding, so the visible item never follows a later external change.
- Safe today: `ConfigSelectionArray` keeps `currentValue` as pure input and derives `toggled` from it; `ColorSelectionArray` / `ConfigSelectionShapeArray` follow the same shape; the dashboard cards (`DashboardSpinCard`, `DashboardToggleCard`, …) recompute `control.get()` on every read; the overview search results already install a `Binding` (`modules/ii/overview/SearchItem.qml:283-348`).

### Why it looks permanent

- Settings pages stay constructed once visited (`SettingsContent.qml:448` — `active: … || everLoaded`), so a stale control survives closing and reopening Settings.
- The right sidebar is kept loaded by default (`Config.qml:961` — `sidebar.keepRightSidebarLoaded: true`), so its copy also survives closing/reopening.
- The only current repair is per-site and manual: `BackgroundConfig.qml:333-337` re-creates the `lockWall` binding with `Qt.binding()` after the selector changes it, and `BarConfig.qml:135-140` / `:176-181` use a `Binding` element for the monitor switches.

### Confirmed by a throwaway hosted probe

`QUICKSHELL_TEST_FILES=tst_sync_probe.qml qs -p tests/shell-tests` (probe deleted afterwards) created two live copies of each widget bound to the same value, self-assigned one copy like a user click, then changed the shared value:

- plain `ConfigSwitch` stayed on the old value → **binding was destroyed**;
- plain `ConfigSpinBox` stayed on the old value;
- plain `ConfigSlider` stayed on the old value;
- plain `ConfigComboBox` kept the old `currentIndex` after `currentValue` changed;
- adding `Binding { target: <control>; property: "checked" | "value"; value: <config>; restoreMode: Binding.RestoreBinding }` made every one of them follow the external change again.
- `passed=9 failed=0` in the final probe; the stale-value and restored-sync cases for all four control types were exercised.

### Duplicate inventory

Status legend: **LIVE** = both sides are declarative/service-backed; **STALE** = a control goes stale after its own first interaction (the reported symptom); **ONE-SHOT** = the other side writes imperatively, so only the control that was used goes stale; **KEY-PAIR** = two config leaves describe the same user intent.

#### Right sidebar (the reported “right quick menu”)

| Parameter | Settings surface | Other surface | Status |
|---|---|---|---|
| `sidebar.quickToggles.android.columns` | `InterfaceConfig.qml:468-479` `ConfigSpinBox` | `AndroidQuickPanel.qml:283-296` `ConfigSpinBox` (edit mode) | **STALE** both ways — the reported columns bug |
| `sidebar.quickToggles.style` | `InterfaceConfig.qml:447-467` selection array | `AndroidQuickPanel.qml:38-43` derived `editTab`/`editTabs` | LIVE value; `editTab` can point at a removed tab |
| `sidebar.media.artColors` | `InterfaceConfig.qml:276-281` `ConfigSwitch` | `SidebarPlayerControl.qml:602-607` `ConfigSwitch` (left sidebar) | **STALE** |
| `custom.colorizeIcon` | `BarConfig.qml:491-496` `ConfigSwitch` (+ dashboard catalog) | `IconPickerDialog.qml:76-84` `ConfigSwitch` | **STALE** |
| `background.widgets.glass.enable` | `InterfaceConfig.qml:139-144` `ConfigSwitch` | Settings dashboard catalog | **STALE** (settings-internal) |

#### Bar widgets and popups

| Parameter | Settings surface | Other surface | Status |
|---|---|---|---|
| `profile.avatarPicture` | `Profile.qml:339-387`, `DashboardHomePage.qml:533-583` | `AvatarPopup.qml:371,438` | LIVE (selection is computed from config) |
| `hyprland.input.kbLayout` | `HyprlandInput.qml:31-47` `ConfigMultiSelect`; `BarConfig.qml:893-911` text field | `HyprlandXkbIndicator.qml:54`, waffle `KeyboardLayoutButton.qml:31` | LIVE value via `HyprlandConfig`; **KEY-PAIR** below |
| `waffles.bar.keyboardLayouts` | `BarConfig.qml:893-911` | waffle bar reads it at `KeyboardLayoutButton.qml:11` | **KEY-PAIR** — the bar reorder writes only `kbLayout`, so the offered list stays old |
| `bar.showFrame` | `BarConfig.qml:312-325` `ConfigSwitch` | `SettingsQuickControls.qml:391-394` (overview search inline control) | **ONE-SHOT** on the page |
| `notifications.position` | `BarConfig.qml:364-370` `ConfigComboBox` | `DashboardSettingsCatalog.qml:160` select | **STALE** combo display after a selection |
| `bar.media.preferredPlayer` | `BarConfig.qml:830-846` `ConfigTextArea` | `DashboardSettingsCatalog.qml:164` | **ONE-SHOT** on the page |
| `bar.widgetStyles` | `SettingsQuickControls.qml:409-410` reset only | `BarGroup.qml:90-102` + `BarGroupStylePopup.qml` sliders | No live duplicate; leave out of this plan |

#### Wallpaper surfaces (desktop right-click menu and picker)

| Parameter | Settings surface | Other surface | Status |
|---|---|---|---|
| `background.centeredWallpaper` | `BackgroundConfig.qml:378-381` `ConfigSwitch` | `WallpaperSubmenu.qml:147-148` `ConfigSwitch` | **STALE** |
| `background.centeredWallpaperOnlyWhenLocked` | `BackgroundConfig.qml:387-390` `ConfigSwitch` | `WallpaperSubmenu.qml:155-157` `ConfigSwitch` | **STALE** |
| `background.centeredWallpaperSize` | `BackgroundConfig.qml:433-442` `ConfigSlider` | `WallpaperSubmenu.qml:187-193` `ConfigSlider` | **STALE** |
| `background.centeredWallpaperShape` | `BackgroundConfig.qml:409-421` shape array | `WallpaperSubmenu.qml:164-168` shape array | LIVE |
| `background.centeredWallpaperColor` | `BackgroundConfig.qml:427-429` colour array | `WallpaperSubmenu.qml:178-180` colour array | LIVE |
| `background.wallpaperAnimation` | `BackgroundConfig.qml:326-328` selection array | `WallpaperSubmenu.qml:227-234` read-through buttons | LIVE |
| `appearance.palette.type` | `QuickConfig.qml:627-633` read-through | `WallpaperSubmenu.qml:79,112` read-through | LIVE |
| `background.lockWall` | `BackgroundConfig.qml:223-233` + manual re-bind at `:333-337` | `WallpaperSelectorContent.qml:187` | LIVE via ad-hoc `Qt.binding` — replace with the shared idiom |
| `wallpaperSelector.showSearchbar` | `BackgroundConfig.qml:1737-1743` `ConfigSwitch` | `WallpaperSelectorContent.qml:223,542` writes `false` | **ONE-SHOT** |
| `wallpaperSelector.useSystemFileDialog` | `BackgroundConfig.qml:1677-1683` `ConfigSwitch` | `WallpaperSelectorContent.qml:749` writes `true` | **ONE-SHOT** |
| `wallpaperSelector.userPath` | `BackgroundConfig.qml` `ConfigTextArea` | `DashboardSettingsCatalog.qml` | **ONE-SHOT** (settings-internal) |

#### Desktop widget menu and clock widget

| Parameter | Settings surface | Other surface | Status |
|---|---|---|---|
| `background.widgetsLocked` | — | `WidgetsSubmenu.qml:37-38` `ConfigSwitch`; `AbstractWidget.qml:39` right-click toggle | **STALE** in the submenu after its own toggle |
| `background.widgets.clock.cookie.sides` / `dialNumberStyle` / `hourHandStyle` / `minuteHandStyle` / `secondHandStyle` / `dateStyle` | `BackgroundConfig.qml:786-867` | `CookieClock.qml:40-50` `applyStyle()` AI preset | **STALE** for the six controls after use; the preset overwrites them live |

#### Overview search (every settings option is also editable there)

`LauncherSearch.qml:404` attaches `SettingsQuickControls.controls[...]` to every matching result and `SearchItem.qml:283-350` renders it with `Binding`-guarded `StyledSwitch` / `StyledSpinBox` / `ConfigSlider` / `ConfigSelectionArray`. The search copy is always right; the Settings page copy is the one that can go stale. This makes the inventory effectively “every `ConfigSwitch` / `ConfigSpinBox` / `ConfigSlider` / `ConfigTextArea` / `ConfigComboBox` in a settings page”.

#### Settings-internal duplicates (classic pages vs dashboard catalog)

`DashboardSettingsCatalog.qml` reads through getters, so it is always current. The classic pages share keys with it for at least: transparency (`enable`, `automatic`, `backgroundTransparency`, `contentTransparency` — `InterfaceConfig.qml:126-168`), `settings.style`, `bar.showFrame`, `notifications.position`, `custom.colorizeIcon`, `background.widgets.glass.enable`, `background.widgets.clock.cookie.*`, `screenRecord.savePath`, `screenSnip.savePath`, `search.engineBaseUrl`, `search.prefix.*`, `crosshair.code`, `overlay.floatingImage.imageSource`, `bar.weather.city`, `bar.media.preferredPlayer`, `wallpaperSelector.userPath`, dock and Hyprland values. They are lower priority than Settings ↔ outside panels but use the same fix.

#### Already covered by the previous time-format plan

`time.format` ↔ `time.secondPrecision` are coupled keys handled in `005-time-format-settings.md` (`StringUtils.setFormatSeconds`, normalized in `DateTime`). Keep that behaviour; it is the model for the `waffles.bar.keyboardLayouts` ↔ `hyprland.input.kbLayout` pair.

## Constraints

- Keep every duplicate entry point. Do not remove or hide a control because the same value exists elsewhere.
- No config schema/key rename. Existing user configs must load unchanged.
- Do not change the visual design, labels, ordering or translation keys (`tst_translation.qml` asserts the exact `en_US` key count).
- Do not mass-migrate all ~200 `ConfigSwitch` usages. Touch only controls for parameters that exist in more than one surface; the shared widget classes may change only where the change is local and provably safe (`ConfigComboBox`’s inner index).
- Re-sync must be idempotent: a handler that writes the config must no-op when the value already matches, otherwise a `Binding` re-application would echo writes.
- The working tree already adds `ConfigSwitch.userToggled(bool)` and migrates `HyprOptionSwitch` to it; keep that API and do not revert it.
- Tests must never touch the real `~/.config/illogical-impulse/config.json`; follow the temporary-config pattern in `tst_config.qml`.

## Tasks

| # | Task | Agent | Priority | Status | Dependencies |
|---|------|-------|----------|--------|--------------|
| 1 | Add a reusable `ConfigBinding` re-sync element and document the idiom | frontend | 1 | DONE | — |
| 2 | Fix `ConfigComboBox` so the inner `currentIndex` keeps following `currentValue` | frontend | 1 | DONE | — |
| 3 | Sync right-sidebar/left-sidebar duplicates (columns, artColors, colorizeIcon) | frontend | 1 | DONE | 1 |
| 4 | Sync desktop right-click wallpaper/clock duplicates | frontend | 1 | DONE | 1 |
| 5 | Sync wallpaper-picker toggles and replace the `lockWall` ad-hoc re-bind | frontend | 1 | DONE | 1 |
| 6 | Sync settings-internal page/dashboard duplicates (transparency, combos, text fields, switches) | frontend | 2 | PARTIAL | 1, 2 |
| 7 | Fix the `waffles.bar.keyboardLayouts` ↔ `hyprland.input.kbLayout` key pair | backend | 2 | DONE | — |
| 8 | Coerce the right sidebar’s `editTab` when quick-toggle style changes | frontend | 2 | DONE | — |
| 9 | Add the static sync guard + parameter allowlist | qa | 2 | DONE | 1-6 |
| 10 | Add hosted `tst_config_sync.qml` for all five config control types | qa | 2 | DONE | 1, 2 |
| 11 | Verification pass (compile, hosted suite, live repro) | qa | 1 | PARTIAL | 1-10 |

### Task 1 — `ConfigBinding`

Add `modules/common/widgets/ConfigBinding.qml`:

```qml
import QtQuick

// Keeps a user-writable control property bound to the config after the
// control overwrites it on user input. Place it inside the control and give
// the control an id.
Binding {
    restoreMode: Binding.RestoreBinding
}
```

Usage:

```qml
ConfigSpinBox {
    id: columnsBox
    value: Config.options.sidebar.quickToggles.android.columns
    onValueChanged: {
        if (value === Config.options.sidebar.quickToggles.android.columns) return;
        Config.options.sidebar.quickToggles.android.columns = value;
    }
    ConfigBinding {
        target: columnsBox
        property: "value"
        value: Config.options.sidebar.quickToggles.android.columns
    }
}
```

Add a short comment block in the file explaining why `Binding` (and not a two-way `property alias`) is required: the property must stay declarative so a value written by another surface re-applies, while the control remains free to show its own intermediate state during a drag.

Do **not** wrap `ConfigSelectionArray` / `ColorSelectionArray` / `ConfigSelectionShapeArray` — their value property is never self-assigned.

### Task 2 — `ConfigComboBox` internal index fix

`currentValue` is not self-assigned, so the usage-side binding is fine; the break is on the inner `currentIndex` (both `comboBox` and `searchComboBox`). Add, inside `ConfigComboBox.qml` next to each inner control:

```qml
Binding {
    target: comboBox
    property: "currentIndex"
    value: {
        const index = root.model.findIndex(item => item.value === root.currentValue);
        return index !== -1 ? index : 0;
    }
    restoreMode: Binding.RestoreBinding
}
```

Repeat for `searchComboBox`. Replace the inline `currentIndex: { … }` binding with the `Binding` element (or leave the inline binding as the initial value — the `Binding` element takes over and re-applies on every `currentValue`/`model` change). One change fixes all 35 `ConfigComboBox` call sites, including `notifications.position`, `language.ui`, `settings.style` and `wallpaperSelector.*`.

### Task 3 — right sidebar / left sidebar

Add `ConfigBinding` to:

- `modules/ii/settings/pages/InterfaceConfig.qml:468-479` (`columns`) and `modules/ii/sidebarRight/quickToggles/AndroidQuickPanel.qml:283-296` (`columns`). Give both spin boxes ids. Add the no-op guard from Task 1 so the two re-syncs cannot ping-pong.
- `InterfaceConfig.qml:276-281` and `SidebarPlayerControl.qml:602-607` (`sidebar.media.artColors`, `property: "checked"`).
- `BarConfig.qml:491-496` and `IconPickerDialog.qml:76-84` (`custom.colorizeIcon`, `property: "checked"`).
- `InterfaceConfig.qml:139-144` (`background.widgets.glass.enable`, settings dashboard duplicate) — same fix.

Also make the quick-toggle order editor write atomically (it already replaces the whole array in `AndroidQuickPanel.qml:126-133`; keep that, do not switch to in-place mutation).

### Task 4 — desktop right-click duplicates

In `modules/common/widgets/WallpaperSubmenu.qml` and the matching settings controls:

- `centeredWallpaper` (`:147-148`) and `BackgroundConfig.qml:378-381` — `ConfigBinding` property `"checked"`.
- `centeredWallpaperOnlyWhenLocked` (`:155-157`) and `BackgroundConfig.qml:387-390` — same.
- `centeredWallpaperSize` (`:187-193`) and `BackgroundConfig.qml:433-442` — `ConfigBinding` property `"value"` on both sliders.

Clock widget: for the six cookie-clock keys, add `ConfigBinding` to the controls in `BackgroundConfig.qml:786-867` so a preset applied by `CookieClock.applyStyle()` is reflected in the open settings pane. Also make `applyStyle()` a no-op when all six values already match, to avoid needless writes.

### Task 5 — wallpaper picker

- `wallpaperSelector.showSearchbar`: add `ConfigBinding` to `BackgroundConfig.qml:1737-1743` (`"checked"`). The selector’s imperative `= false` writes at `WallpaperSelectorContent.qml:223,542` stay as user actions.
- `wallpaperSelector.useSystemFileDialog`: add `ConfigBinding` to `BackgroundConfig.qml:1677-1683` (`"checked"`). Keep the fallback write at `WallpaperSelectorContent.qml:749`.
- `background.lockWall`: replace the manual `Connections { onLockWallChanged: syncWallpaperSwitch.checked = Qt.binding(...) }` at `BackgroundConfig.qml:333-337` with a `ConfigBinding` on `:223-233`. Behaviour must stay identical: turning “Use same wallpaper for both” on clears `lockWall`; turning it off leaves the lock wallpaper empty until the picker sets one.
- `background.widgetsLocked`: add `ConfigBinding` to `WidgetsSubmenu.qml:37-38`. The right-click toggle in `AbstractWidget.qml:39` stays the second entry point.

### Task 6 — settings-internal duplicates

Apply the same `ConfigBinding` to controls whose key is also exposed by `DashboardSettingsCatalog.qml` / `SettingsQuickControls.qml`.

Implemented in this pass:

- `InterfaceConfig.qml` and `AppearanceConfig.qml` — `appearance.transparency.enable`, `.automatic`, `.backgroundTransparency`, `.contentTransparency` (both pages now stay mirrored).
- `BarConfig.qml` — `bar.showFrame`, `bar.media.preferredPlayer`, `waffles.bar.keyboardLayouts`.
- `notifications.position` — covered by the internal `ConfigComboBox` fix (Task 2), no per-site element.
- `custom.colorizeIcon`, `background.widgets.glass.enable`, `background.widgets.clock.cookie.sides`, the centred-wallpaper keys and the picker toggles — covered by Tasks 3-5.

Deferred (page ↔ dashboard/search only; those surfaces read through getters and are already correct): the remaining dock/Hyprland/search-prefix/text-field keys in the inventory. They do not have a second *panel* entry point, so they are not part of the reported symptom. If they are brought in later, add the key to `tests/config-sync-params.txt` first and let the scanner list the sites.

### Task 7 — `waffles.bar.keyboardLayouts` ↔ `hyprland.input.kbLayout`

`BarConfig.qml:901-911` writes both, but the waffle bar’s `KeyboardLayoutButton.applyLayout()` (`modules/waffle/bar/KeyboardLayoutButton.qml:31`) writes only `hyprland.input.kbLayout`. Make the bar write both leaves (or derive `waffles.bar.keyboardLayouts` from `kbLayout` when the list is reordered). Prefer a single helper in `HyprlandConfig`/`KeyboardLayouts` that applies a layout order and keeps the two config leaves equal, so every surface uses one path. Add a test for the equal-after-reorder invariant.

### Task 8 — right sidebar `editTab`

`SidebarRightContent.qml:38` computes `editTab` from the style at construction, and `editTabs` (`:39-43`) drops the `toggles` tab in classic mode. If the style is changed in Settings while the panel is kept loaded, the toolbar can select a tab that no longer exists. Replace the plain property with a coercion that always resolves to an id present in `editTabs` (e.g. a `Connections` on `Config.options.sidebar.quickToggles.style` or a computed getter with an explicit setter), without changing the user’s choice when it is still valid.

### Task 9 — static sync guard

Add `tests/check-config-sync.py` and `tests/config-sync-params.txt`.

- The allowlist contains one config path per line: the parameters that are deliberately exposed in more than one surface (start with the inventory above).
- The scanner walks QML files, finds blocks of `ConfigSwitch|ConfigSpinBox|ConfigSlider|ConfigTextArea`, and for every `(checked|value): Config.options.<path>` where `<path>` is in the allowlist, requires a sibling `ConfigBinding { … }` inside the same block.
- `ConfigComboBox` is excluded: its `currentValue` is not self-assigned and the widget keeps its inner index in sync itself (Task 2). Pure-input arrays are not editable types, so they are naturally exempt.
- Exit non-zero with `file:line: <path> has no ConfigBinding` otherwise. `tests/qml-compile-check.sh` now calls the scanner on every run, so the usual gate covers it.
- Prove the guard by seeding one violation locally, seeing it fail, then removing the seed.

### Task 10 — hosted sync test

Add `tests/shell-tests/tst_config_sync.qml`, based on the throwaway probe that produced the 9/9 result above. Create two live copies of each widget bound to the same property, self-assign one the way a user interaction does, then change the shared property and assert:

- `ConfigSwitch` (`checked`) follows when a `ConfigBinding` is present;
- `ConfigSpinBox` (`value`) follows;
- `ConfigSlider` (`value`) follows (wait for the `SmoothedAnimation` between writes);
- `ConfigTextArea` (`value`) follows;
- `ConfigComboBox` (`comboBox.currentIndex`) follows `currentValue` after a selection;
- two `ConfigBinding`-guarded copies written from either side converge on the same value.

Register the file in `tests/shell-tests/shell.qml`’s `testFiles` list (and keep `tests/functional-coverage.sh` in sync).

### Task 11 — verification

- `bash tests/qml-compile-check.sh` for the whole tree.
- `QUICKSHELL_TEST_FILES=tst_config_sync.qml bash tests/run-shell-tests.sh` (or `qs -p tests/shell-tests`) → all pass.
- `python3 tests/check-config-sync.py modules services welcome.qml` → pass.
- Full hosted suite: no new failures against the known baseline (currently `tst_bar_content` import, `tst_thumbnail_image` ordering, plus the flaky ones noted in plan 001).
- Live-shell repro: open Settings → Interface, open the right sidebar, press edit, change Columns in the sidebar, close edit, confirm the Settings spin box shows the new count; then change it in Settings and confirm the sidebar edit box shows it. Repeat after touching both controls twice.
- Live checks for art colors, colorize icon, centered wallpaper, picker toggles, overview search → Settings.

## Done When

- [ ] Changing `sidebar.quickToggles.android.columns` in either the right sidebar edit box or Settings updates the other control immediately, including after both controls have been used.
- [ ] `sidebar.media.artColors` and `custom.colorizeIcon` stay mirrored between Settings and the left sidebar / icon picker.
- [ ] Centered-wallpaper switch, “only when locked” and size stay mirrored between Settings and the desktop right-click menu.
- [ ] Picker’s search-bar/system-dialog fallbacks are reflected in the Settings switches; the “use same wallpaper” switch still clears `lockWall` and no longer needs the `Qt.binding` re-arm.
- [ ] The widget-lock switch and the six cookie-clock controls reflect changes made by the other surface / AI preset.
- [ ] `notifications.position`, `bar.showFrame`, `bar.media.preferredPlayer` and the transparency controls stay mirrored between the classic page, the dashboard and the overview search inline control.
- [ ] Reordering the layout from the waffle bar keyboard button updates both `hyprland.input.kbLayout` and `waffles.bar.keyboardLayouts`.
- [ ] Switching quick-toggle style while the right sidebar is open leaves the edit toolbar on a valid tab.
- [x] `tests/check-config-sync.py` passes on the tree and fails on a seeded violation.
- [x] `tst_config_sync.qml` passes for switch, spin, slider, text area, combo and two-way convergence.
- [x] No translation-key changes; the touched files pass `tests/qml-compile-check.sh` and the hosted suite shows no new failures (the full-tree lint still reports the pre-existing `GlobalStates.qml` `boolean` annotation).
- [ ] Manual live-shell checklist above is done on the running shell.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-11-18 | Keep both controls for every duplicated parameter; fix the data path instead of removing a surface. | The duplicates are deliberate shortcuts (the right sidebar’s edit mode and the desktop context menus are faster than opening Settings). Removing them would regress the UX the user explicitly wants to keep. |
| 2026-11-18 | Use a `Binding` element (`ConfigBinding`) per duplicated control instead of migrating all ~200 `ConfigSwitch` usages to `onUserToggled`. | The binding break is real and confirmed, but a full API migration is a large, risky diff. A per-site `Binding` fixes the exact duplicates, matches the two patterns already in the tree (`BarConfig`, `SearchItem`), and does not change widget behaviour. The `userToggled` signal already added in the working tree stays available for a later cleanup. |
| 2026-11-18 | Fix `ConfigComboBox` inside the widget, not at the call sites. | The broken binding is on the inner `currentIndex`, which call sites cannot reach; one internal `Binding` fixes all 35 combos. |
| 2026-11-18 | Make re-sync handlers no-ops when the value already matches. | A `Binding` re-applies the config value; without the guard every re-application would echo a write back into the config and could ping-pong between two copies. |
| 2026-11-18 | Add a scanner plus an explicit duplicated-parameter allowlist. | The failure mode is invisible to `qmllint` and to the compile check; a list of parameters makes the guard precise instead of demanding a `Binding` on every control in the shell. |
| 2026-11-18 | Treat dashboard cards and overview search as read-through and leave them alone. | They already recompute from `control.get()`/config on every read and cannot go stale. Only the classic pages and panel controls need the fix. |
| 2026-11-18 | Do not rename or merge config keys in this plan, except the `waffles.bar.keyboardLayouts` mirror write. | Renaming needs a migration path and would invalidate every user preset; the known key-pair bug is fixed by writing both leaves through one helper. |

## Progress Notes

- [2026-11-18] Audit completed against the working tree (which already contains unrelated in-progress edits, including `ConfigSwitch.userToggled` and the VNC page removal — none of those were modified).
- [2026-11-18] A throwaway hosted probe (`tst_sync_probe.qml`, deleted after the run) confirmed the binding-break root cause for `ConfigSwitch`, `ConfigSpinBox`, `ConfigSlider` and `ConfigComboBox`, and confirmed that `Binding { restoreMode: Binding.RestoreBinding }` restores two-way sync. Final probe: `passed=9 failed=0`.
- [2026-11-18] Inventory completed by scanning every `Config.options.*` assignment, grouping by shell surface, and reading each duplicate control block. The tables above are the result; the reported columns bug is `InterfaceConfig.qml:468-479` ↔ `AndroidQuickPanel.qml:283-296`.
- [2026-11-18] Confirmed settings pages stay constructed (`SettingsContent.qml:448`) and the right sidebar is kept loaded by default (`Config.qml:961`), which is why a stale control survives closing the window.
- [2026-11-18] Noted that `BackgroundConfig.qml:333-337` and `BarConfig.qml:135-140` already use manual re-binding; this plan replaces them with the shared `ConfigBinding` so there is one idiom.
- [2026-11-18] Implementation:
  - `modules/common/widgets/ConfigBinding.qml` — new `Binding` wrapper with `restoreMode: Binding.RestoreBinding` and the usage contract documented.
  - `ConfigComboBox.qml` — `currentIndexForValue` drives two `Binding` elements (normal + searchable combo); the inline index bindings were removed.
  - Right/left sidebar: `InterfaceConfig` + `AndroidQuickPanel` columns, `InterfaceConfig` + `SidebarPlayerControl` art colours, `BarConfig` + `IconPickerDialog` colourise icon, `InterfaceConfig` glass switch.
  - Desktop menus: `WallpaperSubmenu` centred-wallpaper enable/locked/size; `WidgetsSubmenu` widget lock; `BackgroundConfig` counterparts plus the cookie-clock `sides`.
  - Picker: `BackgroundConfig` search-bar/system-dialog switches; the `lockWall` `Connections { Qt.binding(...) }` workaround was replaced by a `ConfigBinding`.
  - Settings-internal: transparency on both `InterfaceConfig` and `AppearanceConfig`; `BarConfig` show-frame, preferred player, waffle keyboard layouts.
  - `services/HyprlandConfig.qml:setKeyboardLayout` now writes both `hyprland.input.kbLayout` and `waffles.bar.keyboardLayouts`, so a reorder from either bar keeps the other list current.
  - `HyprOptionSwitch` was considered for the same `Binding` treatment, but left alone: it builds on the in-progress `ConfigSwitch.userToggled` / `HyprlandOptions.asBool` work in the tree, so it is not part of this commit.
  - `SidebarRightContent.qml` coerces `editTab` to a valid id when the quick-toggle style changes.
- [2026-11-18] Verification:
  - `python3 tests/check-config-sync.py modules services welcome.qml` → 20 parameters, no missing binding. A seeded violation printed `ConfigSwitch binds sidebar.quickToggles.android.columns without a ConfigBinding` and exited 1, then the seed was removed. The scanner is wired into `tests/qml-compile-check.sh`.
  - `QUICKSHELL_TEST_FILES=tst_config_sync.qml qs -p tests/shell-tests` → 11/11 passed.
  - `bash tests/qml-compile-check.sh <all touched files>` → PASS. The full-tree run still fails only on the pre-existing `GlobalStates.qml` `"boolean" ... unresolved-type` from unrelated in-progress work.
  - Full hosted suite: 34 passed / 4 failed. `tst_bar_content` (known import), `tst_thumbnail_image` (known ordering), `tst_managed_keybinds` (known baseline 2/5) and `tst_appearance`, which passes 8/8 when run alone (ordering flake, not touched by this change).
  - Live-shell repro is still pending: the checkout is not the running config; `./sync.sh` and the manual checklist in Task 11 remain.
