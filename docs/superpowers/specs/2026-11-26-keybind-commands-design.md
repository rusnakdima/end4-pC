# Keybind Commands, Reload, and Capture Lock — Design

Date: 2026-11-26
Repo: `/mnt/Other/THEMES/end4-pC`

## Intent and why

The user cannot make `CTRL + SUPER + R` reload the theme, cannot delete command keybinds from Settings, cannot choose command actions by category when adding a keybind, and sees an existing keybind execute while they are recording a new combination. Each of these is a control gap in the same Settings → Keyboard page and its services.

## Goals

1. `CTRL + SUPER + R` reloads Quickshell through the canonical `GlobalStates.requestShellReload()` path and appears in Settings as an editable Shell bind named “Shell: Reload theme”.
2. Settings can delete a command keybind. For user-added custom commands the bind and its generated command entry both go away; for built-in theme commands only the bind is disabled and the command stays available.
3. The add/edit form offers a category-driven action picker (Media, Shell, Utilities, Window, …) plus a custom-command field. Picking a category narrows the actions; typing a custom command always wins.
4. While a capture is armed, theme global shortcuts are temporarily unregistered so the combination being recorded does not execute. The compositor-side `ShortcutInhibitor` stays.

## Non-goals

- Per-application (“only while app X is focused”) binds. The user clarified that “category” means command type, not window scope.
- Replacing the catalog + overlay + generator persistence model.
- Making raw Lua binds editable.

## Constraints

- Catalog: `defaults/hyprland/keybinds.json` (flat `binds[]`). Generator: `scripts/hyprland/generate_keybinds.py`; validator has a stable-id baseline. Only `command` and listed `global`/dispatch kinds are valid.
- Generated commands: `state/generated-commands.json`, watched by `services/GeneratedCommandShortcuts.qml`; bridge name `quickshell:runCommand:<id>`.
- Overlay: `services/ManagedKeybinds.qml` owns `~/.config/hypr/custom/keybind-overlay.json`; adds, overrides, disabled ids.
- `GlobalShortcut` (Quickshell.Hyprland) has **no `enabled` property**. Its `name` is writable in QML but `setName()` is a no-op after registration in Quickshell 0.3.2 (source and qmltypes verified by the builder check). Runtime name changes therefore cannot unregister a shortcut.
- `ShortcutInhibitor` already exists in `Settings.qml` and `Dashboard.qml`, gated by `GlobalStates.keybindCaptureArmed`.
- `CompositorGlobalShortcut.qml` wraps `GlobalShortcut` for most theme actions; direct `GlobalShortcut` instances are in `services/GeneratedCommandShortcuts.qml:83` (delegate) and `modules/ii/cheatsheet/Cheatsheet.qml:216,225,234`. `GlobalStates.qml` uses only the wrapper.

## Approaches

- **A (chosen): extend the existing catalog + overlay + generator system.** One new `shellReload` theme shortcut, a Commands section that deletes the owning bind, a capture-time name gate on global shortcuts, and an action picker derived from catalog command binds. Reuses one source of truth and existing tests.
- **B: separate user-commands store.** Would duplicate generated commands and need its own sync; rejected.
- **C: symptom patches only.** Would not deliver category-driven commands; rejected.

## Decisions

- Reload dispatch: keep bind-26's id, combo `CTRL + SUPER + R` and category `""`; set `description`/`label` to `Shell: Reload theme`, dispatch `{kind:"global", arg:{kind:"string", value:"quickshell:shellReload"}}`, code `hl.bind("CTRL + SUPER + R", hl.dsp.global("quickshell:shellReload"), { description = "Shell: Reload theme" })`, and drop the old `command` field. Register `CompositorGlobalShortcut { name: "shellReload"; onPressed: root.requestShellReload() }` in `GlobalStates.qml` (the singleton uses `root`, not `GlobalStates`). Stable-id baseline stays valid; update the generated-commands test fixture.
- Delete semantics: overlay-added custom command → `ManagedKeybinds.remove(id)` so the generator drops the command entry. Built-in catalog command bind → `DisabledKeybinds.disableBinds(id, label, binds)` so the bind disappears; the command stays in the catalog-derived picker and can be re-added as a fresh overlay add. The generator/validator contract is unchanged.
- Capture lock (user-confirmed): unload the theme's global-shortcut objects while `GlobalStates.keybindCaptureArmed` is true. Gate `CompositorGlobalShortcut.qml` with a Loader `active` that also requires `!GlobalStates.keybindCaptureArmed` (add `import qs`); empty the `GeneratedCommandShortcuts.qml` Instantiator model during capture; wrap the three `Cheatsheet.qml` shortcuts in Loaders. Shortcuts return when capture ends. No `name` mutation; no attempt to mute raw Hyprland `exec` binds (out of scope and unsafe).
- Action catalog: derive from catalog binds whose `dispatch.kind === "command"` and whose `description` contains `": "`. Category = text before the colon, action label = text after. Expose `HyprlandKeybinds.commandActionIndex` as an array of `{category, label, command, bindId}`. The form's category ComboBox filters the action ComboBox; selecting an action copies only `dispatch.command` into `formCommand`. It does not overwrite `formCategory` or `formName`; a later edit of the command field wins. On edit, match the selected action by command string.
- No `removeForBind` helper: `ManagedKeybinds.remove()` already triggers the generator rewrite and `GeneratedCommandShortcuts.qml` watches the file (5s fallback). Capture flag lifecycle is already wired at `KeyboardConfig.qml:519/529`; no new state is needed.
- UI ordering: reload bind first (small), then delete, capture lock, then action picker + Commands section.

## Parts of the how

- `GlobalStates.qml`: add the `shellReload` shortcut.
- `defaults/hyprland/keybinds.json`: rewrite bind-26; keep id stable so the validator baseline still passes.
- `services/CompositorGlobalShortcut.qml`: gate `name` on capture; add optional `enabled`-like pass-through if needed.
- `services/GeneratedCommandShortcuts.qml`: gate delegate name during capture; expose a `removeForBind(id)`/reload helper if deleting needs an immediate refresh.
- `services/HyprlandKeybinds.qml`: add `commandActionIndex`.
- `modules/ii/settings/pages/KeyboardConfig.qml`: category/action pickers, custom command field, Commands section with delete, bind-26 visibility.
- Tests: Python generator/validator tests for bind-26 dispatch and generated command removal; QML tests for `commandActionIndex` and form selection; hosted tests for delete and capture gating where feasible.

## What is left to the builder

Exact widget placement in `KeyboardConfig.qml`, translations for new labels, and the precise test file names are implementation choices. Behavior and persistence boundaries above are fixed.
