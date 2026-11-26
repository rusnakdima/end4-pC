# Escape, Record Bind, and Hold-to-Repeat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a working `SUPER+SHIFT+R` record bind, make Escape dismiss all top-level overlays as well as transient layers, and make held XF86 volume/brightness keys keep changing their values.

**Architecture:** The keybind catalog remains the only source for binds; `generate_keybinds.py` produces Hyprland Lua and `generated-commands.json`, whose ids are consumed by the `GeneratedCommandShortcuts` singleton. Hold-to-repeat is implemented inside that singleton with a `Timer` driven by `GlobalShortcut.pressed`, not by Hyprland key-repeat. Escape handling stays local to each QML component so edits/search keep priority over dismissal.

**Tech Stack:** Python 3 catalog generator and unittest, QML/QtQuick 6, Quickshell 0.3.2 `GlobalShortcut`, Hyprland 0.57.2 Lua binds, `wpctl`/`brightnessctl`.

**Spec:** `docs/superpowers/specs/2026-11-26-escape-record-and-hold-repeat-design.md`

## Global Constraints

- Never reboot, kill, shut down, restart processes, or reload Hyprland/Quickshell. QML source and newly generated Lua take effect for the running session only after the user reloads it themselves; say so in the final report.
- Generated files are outputs, not sources: edit `defaults/hyprland/keybinds.json`, then regenerate.
- Commands reach Hyprland through `quickshell:runCommand:<id>` global shortcuts (`hl.dsp.exec_cmd()` is a no-op on Hyprland 0.57.2).
- `GlobalShortcut` has `pressed` and `pressed()`/`released()` but no repeat signal, no `enabled` property, and `setName()` is a no-op after registration.
- Session, sleep, poweroff, reload and kill-window binds are never live-tested.
- Settings/Dashboard keep cancel-first Escape via `SettingsEscape.js`; the first Escape cancels an edit/search rather than closing.

## Review Focus

- A missed key release must not leave volume/brightness running away — pinned by `test_repeat_stops_on_pressed_false_and_released`.
- Start-menu search must not swallow Escape while the user is typing — pinned by `test_start_menu_escape_closes_instead_of_returning`.
- Action center / notification center Escape must call the existing close signal so state resets — pinned by `test_sidebar_escape_closes_via_onClosed`.
- The new record bind must not collide with `bind-26` (CTRL+SUPER+R) or other combos — pinned by `test_record_bind_is_unique_and_wired`.
- Settings Escape must remain cancel-first — pinned by `test_settings_escape_still_cancel_first`.

---

### Task 1: Record bind in the catalog

**Files:**
- Modify: `defaults/hyprland/keybinds.json`
- Modify: `tests/shell-tests/state/generated-commands.json`
- Test: `tests/test_record_bind.py` (create)

**Interfaces:**
- Produces: a catalog bind with `id` `utilities-17` (the Utilities group currently ends at `utilities-16`), `combo` `SUPER + SHIFT + R`, `dispatch.kind` `global`, `dispatch.name` `quickshell:regionRecord`, `description` `Utilities: Record region`, `options` `{}`; generator emits it into `generated-commands.json` as a command bridge.

- [ ] **Step 1: Write the failing test**

Create `tests/test_record_bind.py` with `test_record_bind_is_unique_and_wired`: load the catalog, assert exactly one bind has `combo == "SUPER + SHIFT + R"`, assert that bind's `dispatch.kind == "global"`, `dispatch.name == "quickshell:regionRecord"`, and that no other bind shares the combo (ignore `bind-26`, whose combo is `CTRL + SUPER + R`). Also assert the fixture `tests/shell-tests/state/generated-commands.json` contains an entry for that id.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest tests.test_record_bind -v`
Expected: FAIL with "exactly one" / missing id.

- [ ] **Step 3: Add the bind and refresh the fixture**

Append the bind to `binds` in `defaults/hyprland/keybinds.json` using the fields in Interfaces. Regenerate to a temp dir with `python3 scripts/hyprland/generate_keybinds.py --catalog defaults/hyprland/keybinds.json --main-out /tmp/opencode/main.lua --custom-out /tmp/opencode/custom.lua --commands-out /tmp/opencode/commands.json`; copy the generated commands JSON to `tests/shell-tests/state/generated-commands.json`. After the test passes, copy `/tmp/opencode/main.lua` to `/home/dmitriy/.config/hypr/hyprland/keybinds.lua`, `/tmp/opencode/custom.lua` to `/home/dmitriy/.config/hypr/custom/keybinds.lua`, and `/tmp/opencode/commands.json` to `/home/dmitriy/.config/quickshell/end4-pC/state/generated-commands.json` (no reload).

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest tests.test_record_bind -v && python3 scripts/validate_keybind_catalog.py`
Expected: PASS; validator prints `OK: 213 catalog binds` (one more than before).

- [ ] **Step 5: Commit**

```bash
git add defaults/hyprland/keybinds.json tests/shell-tests/state/generated-commands.json tests/test_record_bind.py
git commit -m "feat(keybinds): bind SUPER+SHIFT+R to region record"
```

### Task 2: Hold-to-repeat for volume and brightness

**Files:**
- Modify: `services/GeneratedCommandShortcuts.qml`
- Test: `tests/test_hold_repeat_wiring.py` (create)

**Interfaces:**
- Consumes: `root.runCommand(id)` from `GeneratedCommandShortcuts.qml` (rejects unknown ids); `GlobalShortcut.pressed` / `pressed()` / `released()`.
- Produces: `readonly property var repeatableIds: ["bind-19", "bind-20", "bind-21", "bind-22"]`, a `Timer` with `repeat: true` that calls `runCommand` for the currently held repeatable id; no change to catalog commands.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_hold_repeat_wiring.py` with three tests reading `services/GeneratedCommandShortcuts.qml` as text:
- `test_repeatable_ids_are_only_the_four_xf86_brightness_volume_bridges`: assert the file contains `repeatableIds` and all four ids, and does not list an unrelated id such as `media-8`.
- `test_repeat_stops_on_pressed_false_and_released`: assert the file contains `onPressedChanged`, `onReleased`, and a `Timer` with `repeat: true`; assert `stop()` appears in both `onPressedChanged` and `onReleased` blocks.
- `test_repeat_runs_through_run_command_allowlist`: assert the timer callback contains `runCommand(` and that no `Quickshell.execDetached` call exists outside the existing `runCommand` function.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m unittest tests.test_hold_repeat_wiring -v`
Expected: FAIL with "repeatableIds" missing.

- [ ] **Step 3: Implement the repeat timer**

In `services/GeneratedCommandShortcuts.qml`: add `repeatableIds`, `property string heldRepeatId: ""`, and a `Timer` (`interval: 100`, `repeat: true`, `running: false`, `onTriggered: root.runCommand(root.heldRepeatId)`). In the delegate, add `onPressed`: for repeatable ids run once then set `heldRepeatId` and start a 300 ms one-shot `Timer` that starts the repeating timer only while still pressed; add `onReleased` and `onPressedChanged` handlers that stop both timers and clear `heldRepeatId`. Route every invocation through `root.runCommand(modelData)` and do not bypass the id allowlist.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p 'test_*.py'`
Expected: PASS, including the three new tests and all existing tests.

- [ ] **Step 5: Commit**

```bash
git add services/GeneratedCommandShortcuts.qml tests/test_hold_repeat_wiring.py
git commit -m "feat(shortcuts): repeat held volume and brightness keys"
```

### Task 3: Escape closes transient layers and top-level overlays

**Files:**
- Modify: `modules/ii/desktopMenu/DesktopMenu.qml`, `modules/ii/overlay/StyledOverlayWidget.qml`, `modules/ii/onScreenDisplay/OnScreenDisplay.qml`, `modules/waffle/onScreenDisplay/WaffleOSD.qml`, `modules/waffle/actionCenter/WaffleActionCenter.qml`, `modules/waffle/notificationCenter/WaffleNotificationCenter.qml`, `modules/waffle/startMenu/StartMenuContent.qml`
- Test: `tests/test_escape_wiring.py` (create)

**Interfaces:**
- Consumes: existing close APIs — `root.openCentered(false)` (DesktopMenu), `root.close()` (StyledOverlayWidget), `GlobalStates.osdVolumeOpen` / `GlobalStates[root.currentIndicator’s globalStateValue]` (OSD), `content.close()` plus `onClosed` signal (action/notification center), `GlobalStates.searchOpen = false` (start menu).
- Produces: Escape closes each of those surfaces while leaving sidebar-right, settings cancel-first behavior, and per-component edit/search handlers intact.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_escape_wiring.py` with these tests, each asserting `Qt.Key_Escape` and the named action appear in the named file:
- `test_desktop_menu_escape_closes`: `DesktopMenu.qml` contains `Qt.Key_Escape` and `openCentered(false)`.
- `test_overlay_widget_escape_closes`: `StyledOverlayWidget.qml` contains `Qt.Key_Escape` and `root.close()`.
- `test_osd_escape_closes_both_families`: both OSD files contain `Qt.Key_Escape` and assign `false` to their open state.
- `test_sidebar_escape_closes_via_onClosed`: both Waffle sidebar files contain `Qt.Key_Escape` and `content.close()`.
- `test_start_menu_escape_closes_instead_of_returning`: `StartMenuContent.qml` contains `Qt.Key_Escape` followed by `GlobalStates.searchOpen = false` and no bare `return` in the Escape branch.
- `test_settings_escape_still_cancel_first`: `SettingsEscape.js` still contains the cancel-first branch and `Settings.qml` has no new `Qt.Key_Escape` handler.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m unittest tests.test_escape_wiring -v`
Expected: FAIL on each missing handler.

- [ ] **Step 3: Add Escape handlers**

For each component, add a `Keys.onPressed: event => { if (event.key === Qt.Key_Escape) { <close action>; event.accepted = true; } }` on the focused item/PanelWindow that owns the surface. In `StartMenuContent.qml`, replace the bare `return` in the Escape branch with `GlobalStates.searchOpen = false; event.accepted = true` and keep the Backspace branch untouched. Do not add a global Escape grab and do not modify Settings/Dashboard.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p 'test_*.py' && bash tests/qml-compile-check.sh`
Expected: PASS; QML compile check reports no syntax errors in the modified files.

- [ ] **Step 5: Commit**

```bash
git add modules/ii/desktopMenu/DesktopMenu.qml modules/ii/overlay/StyledOverlayWidget.qml modules/ii/onScreenDisplay/OnScreenDisplay.qml modules/waffle/onScreenDisplay/WaffleOSD.qml modules/waffle/actionCenter/WaffleActionCenter.qml modules/waffle/notificationCenter/WaffleNotificationCenter.qml modules/waffle/startMenu/StartMenuContent.qml tests/test_escape_wiring.py
git commit -m "fix(ui): close overlays and menus with Escape"
```
