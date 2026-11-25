# Keybind Manager Fixes — Design

## Intent

The Settings → Keyboard page must let the user record any chord, remove a
binding, resolve conflicts by keeping one binding or applying offered keys,
search by key combination, and see both kinds of keybind conflict as warnings.

## Goals

1. Capture works even when Hyprland owns the chord (for example SUPER+I while
   Settings is open).
2. Deleting works for overlay adds, catalog shell actions, plain bindings and a
   single alias combo of an action.
3. Duplicate-combo conflicts and one-action-many-combos ("alias") conflicts are
   both visible and resolvable.
4. Search accepts a typed or pressed combination in any spelling.
5. Conflict warnings use an icon and an accent border, not only amber text.

## Non-goals

- Editing raw Lua binds.
- Changing catalog defaults.
- A Hyprland capture submap (rejected in favour of the shortcut inhibitor).
- Cross-compositor keybind management.

## Constraints

- QML and plain JavaScript modules inside `end4-pC`.
- `~/.config/hypr/custom/keybind-overlay.json` remains the source of truth.
- Every write goes through `ManagedKeybinds` or `DisabledKeybinds` and its
  `result.ok` is checked.
- Existing QML tests keep passing; new logic gets unit tests.

## Approach

**Capture:** Quickshell's `ShortcutInhibitor` (`Quickshell.Wayland`) is attached
to the settings window and enabled only while a capture is armed. Hyprland
stops consuming its own shortcuts, so the existing `keyScope` forwarding
receives the chord. An inline text field accepts a typed combination as a
fallback when the compositor does not grant the inhibitor.

**Search:** a keyboard button beside the search field arms the same capture and
puts the pressed combination into the shared filter. Typed queries are matched
against combos after canonicalising modifiers and separators, so `super+i`,
`super i` and `SUPER + I` are equivalent.

**Conflicts:** `HyprlandKeybinds` exposes an alias index (action → its combos).
`KeybindConflicts.groupsFrom` returns both duplicate-combo and alias groups.
The conflict panel offers "Use only this one" (remove every other holder) and
"Apply suggested keys to all others", alongside the existing per-holder Move.

**Delete:** alias rows get a per-combo delete using the restore id
`shell:<action>:<combo>`; managed deletes report failures instead of silently
doing nothing.

**Warnings:** rows with a duplicate combo or an alias conflict get a warning
icon and an accent border; the alias line becomes an amber warning.

## Verification

Unit tests for the combo parser, canonical matcher, combo-aware filter, alias
groups, keeper selection, removal plan and `fixHolder` result handling. Manual
checks: SUPER+I capture, per-alias delete, use-only-this, apply offers, typed
and pressed search, warning rendering, and restore from Deleted keybinds.
