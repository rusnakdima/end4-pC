# Keybind Manager: create and edit keybinds from Settings

> A form on Settings → Keyboard that creates new keybinds into a panel-managed block of `~/.config/hypr/custom/keybinds.lua` and edits them afterwards — with readable word key caps (Super, Ctrl, Shift…), a live "is this key already used?" status, and a tip under every field.

**Status**: Completed
**Created**: 2026-11-17
**Owner**: general

## Goal

1. A **Keybind manager** section on the Keyboard settings page with a form that **creates** a keybind: name, category, app/command, and a captured key combination, saved with one click.
2. The same form **edits and deletes** keybinds the panel created.
3. Every combination is displayed as **word keys** — `Super`, `Ctrl`, `Shift`, `Enter`, `/` — not raw Hyprland tokens (`SUPER`, `CTRL`, `Return`, `Slash`), in the form *and* in the existing shortcut rows of the same page.
4. The form shows **whether the captured combination is already used** (`Available` vs `Also used by …`) before the user saves.
5. Every field carries a **tip** (category, app/command, keys) so setup is self-explanatory.
6. Existing edit paths keep working: shell shortcuts and other binds stay rebindable by their current click-and-press capture (they are not routed through the new form — their only editable property is the key, which the rows already handle, and moving them would risk the proven flow for no new capability).

## Context

### There is no way to create a keybind today

- `modules/ii/settings/pages/KeyboardConfig.qml:302-564` — the page has *Keyboard color*, *Shell shortcuts* and *Other keybinds*. Every edit path **rebinds an existing bind** by capturing keys and writing `~/.config/hypr/custom/keybind_overrides.conf` (`services/HyprlandBindOverrides.qml`). Nothing writes a new `hl.bind(...)` line anywhere.
- New keybinds must live in `~/.config/hypr/custom/keybinds.lua`: `hyprland.lua` requires `custom.keybinds` only when that file exists (live `~/.config/hypr/hyprland.lua:31-33`), and `scripts/hyprland/get_keybinds.py:225-238` walks `hypr/custom/` for **every** `*.lua`, so binds written there show up in the cheatsheet and in *Other keybinds* after a reload. `custom/` is live-only and excluded from `sync.sh:92` (`--exclude='/custom/'`), so the panel can own a block inside it safely.

### The managed block is the write target

- The panel owns one marker-delimited block at the end of `custom/keybinds.lua`:
  `-- >>> end4-pC managed keybinds >>>` … `-- <<< end4-pC managed keybinds <<<`.
  Everything outside the markers is the user's and must survive byte-for-byte (the file already holds two hand-written binds).
- Inside the block each entry is one line — `hl.bind("SUPER + K", hl.dsp.exec_cmd("cmd"), {description = "Name"})` — preceded by `--##! <category>` headings (grouped, written when the category changes; the parser turns them into cheatsheet sections, `get_keybinds.py:143-156`) and a `-- panel-id: <id>` comment (ignored by the parser: it matches neither the heading regex `^(-+#+)!\s*`, `--#/#`, nor `hl.bind`) so edit/delete can find the line again.
- `get_keybinds.py:93` extracts the description with `description\s*=\s*"([^"]+)"` → the stored **description must not contain `"`**; the command is Lua-escaped and single-line. Lines with net-unbalanced parentheses inside the command confuse the parser's depth count (`get_keybinds.py:176-183`) — documented limitation, the bind still works, only display of *following* lines degrades.
- Writing the file is `FileView` read-modify-write + `hyprctl reload`, exactly the `HyprlandBindOverrides` pattern (`:84-103`): `pendingWrite` guard, `mkdir -p` first, reload after `setText`.

### Word keys and status already have building blocks

- `modules/common/functions/KeyCombos.js:11-55` holds the Hyprland key-name table; a new pure `displayLabel(part)` maps `SUPER→Super`, `CTRL→Ctrl`, `SHIFT→Shift`, `Return→Enter`, `Slash→/`, `mouse:274→Mouse 2` … and is unit-tested in `tst_keycombos.qml` (stage 1, `qmltestrunner`).
- The form's status line reuses `HyprlandKeybinds.repeatUsers(combo, selfId)` (`services/HyprlandKeybinds.qml:155-159`) and the page's existing `repeatSentence`/`conflictColor` (`KeyboardConfig.qml:30-40`), which *Other keybinds* rows already use — the form just shows it **before** saving instead of after.
- Capture is already routed page-wide: `modules/ii/settings/Settings.qml:82-86` forwards presses to `GlobalStates.currentPageInstance.handleCapturedKey`. The form captures under its own id (`"form"`) inside `KeyboardConfig.qml:275-296`; the rest of the machinery (10 s timeout, Escape, settings-close) is untouched.

### Form controls and tips

- `ContentSection` takes a `hint` + `hintIcon` tooltip (`modules/common/widgets/ContentSection.qml:14-15,117-145`); field tips are small `colSubtext` lines; `NoticeBox` for the "written to custom/keybinds.lua" note.
- App picker: `ConfigComboBox { searchable: true }` over `AppSearch.list` (`services/AppSearch.qml:47-53`, `DesktopEntry.command` list joined + shell-quoted via `StringUtils.shellSingleQuoteEscape`, field codes `%x` filtered out); it only fills the editable command field — the field stays the single source of truth.
- Category: `MaterialTextField` plus clickable chips built from `HyprlandKeybinds.categories` (`services/HyprlandKeybinds.qml:37-44`); empty category is allowed and written without a heading (grouped first in the block; caveat: such entries inherit whatever section is open above the block — cosmetic only, the bind still works).

### Gates (baselines recorded 2026-11-17)

- `tests/qml-compile-check.sh` → PASS.
- `tests/run-shell-tests.sh` → **33 passed / 2 pre-existing failures** (`tst_bar_content`: harness cannot resolve `qs.modules.ii.bar`; `tst_thumbnail_image`: 1). New work must not add failures.
- `tests/functional-coverage.sh` → **16 pre-existing UNMAPPED**, already red; new units must be mapped or exempted so it stays at 16.
- `tests/shell-tests/tst_translation.qml` asserts the **exact** en_US key count (1790, 5 sites) — every new `Translation.tr` string must be added to `translations/en_US.json` (the harness fixture is a symlink) and the count updated.
- `tests/icon-audit.py` verifies every `MaterialSymbol` name against the pinned pack.

## Constraints

- Never rewrite anything outside the managed markers in `custom/keybinds.lua`; the file is the user's.
- The stored description cannot contain `"`; commands are single-line Lua-escaped strings. Both are validated in the form.
- No new `function` declarations in `services/*.qml` or `modules/{common/widgets,ii}/**/*.qml` without a mapped test or a written exemption — otherwise `functional-coverage.sh` grows past 16.
- Pure logic goes in `modules/common/functions/*.js` so `qmltestrunner` covers it without Quickshell (repo rule, see `KeyCombos.js:4-6`).
- The existing capture flow (rows, `handleCapturedKey`, Escape, timeout) must keep behaving exactly as it does today.
- New keybinds are written only after the form validates name + command + keys; one `hyprctl reload` per save, never per keystroke.
- Every new user-visible string goes through `Translation.tr`.

## Tasks

| # | Task | Agent | Priority | Status | Dependencies |
|---|------|-------|----------|--------|--------------|
| 1 | Plan artifacts: this file + `.agents/results/plan-*.json` | general | 1 | DONE | — |
| 2 | `KeyCombos.displayLabel()` word-key mapping + cases in `tst_keycombos.qml` | frontend | 1 | DONE | 1 |
| 3 | Pure `modules/common/functions/KeybindStore.js` (parse/render/splice managed block, escape/validate) + `tst_keybindstore.qml` | frontend | 1 | DONE | 1 |
| 4 | `services/ManagedKeybinds.qml` (FileView over `custom/keybinds.lua`, `create/update/remove`, `hyprctl reload`) + hosted `tst_managed_keybinds.qml` on a temp path + `EXPLICIT_MAP`/`shell.qml` listing | frontend | 1 | DONE | 3 |
| 5 | UI: Keybind manager section in `KeyboardConfig.qml` — form (name, category + chips, command + app picker, capture box with word caps and live used-status, field tips, save/cancel/delete), managed list rows, form capture branch, word labels in existing rows | frontend | 1 | DONE | 2, 4 |
| 6 | Translations: new `Translation.tr` strings → `translations/en_US.json`, update the exact count in `tst_translation.qml` | frontend | 2 | DONE | 5 |
| 7 | Verification: compile check, qml+shell tests (no new failures), coverage stays 16, icon audit, duplicate-signal check | general | 1 | DONE | 2-6 |
| 8 | Sync to live tree, smoke-test create/edit/delete against `hyprctl binds`, update plan status, commit and push | general | 1 | DONE — synced with `./sync.sh --force` (user-approved despite the locked session); live smoke passed | 7 |

### Gate results (run 2026-11-17, after implementation)

- `tests/qml-compile-check.sh` → **PASS** (includes `check-duplicate-signals.py` + `icon-audit.py` over the tree).
- `tests/run-qml-tests.sh` / `tests/run-shell-tests.sh` → **34 passed / 2 pre-existing failures** (`tst_bar_content`, `tst_thumbnail_image`); the +1 passed file is the new `tst_managed_keybinds.qml` (7 cases).
- `tests/functional-coverage.sh` → exactly **16 UNMAPPED** (unchanged; `ManagedKeybinds` is in `EXPLICIT_MAP`).
- `tst_translation.qml` → en_US count updated **1790 → 1814** (+24 new keys), all 5 assertion sites.
- `scripts/hyprland/get_keybinds.py --path <sample>` → renders and parses: sections `Apps`/`System`, descriptions and combos extracted.

### Live smoke (run 2026-11-17, session was locked → `./sync.sh --force` with user approval)

A one-off hosted test (`tst_live_smoke.qml`, run with `QUICKSHELL_TEST_FILES`, removed afterwards) pointed `ManagedKeybinds` at the **real** `~/.config/hypr/custom/keybinds.lua` and drove the exact calls the form makes:

- **create** → `hl.bind("SUPER + CTRL + ALT + F12", …, {description = "zz smoke test"})` landed inside the markers; `hyprctl reload` → `hyprctl binds -j` shows it (key `F12`, modmask 76, `HL.Dispatcher(exec_cmd)`).
- **update** → renamed line only; the old bind disappears from `hyprctl binds` after reload.
- **delete** → no test bind in file or binds afterwards; content outside the markers byte-identical (the empty marker block stays, by design); `sync.sh`'s own `hyprctl reload` failed only on the harness's stale `HYPRLAND_INSTANCE_SIGNATURE` (re-run with the live signature: `ok`).
- Quickshell survived the forced mid-lock hot-reload (`qs -c end4-pC` reachable), and a final `./sync.sh --dry-run` reports *quickshell matches the checkout*. The user's file keeps its two hand-written binds; backup of the pre-smoke bytes: `/tmp/opencode/keybinds.lua.orig-backup`.

### Post-completion fixes (user live testing, 2026-11-17)

The user drove the real form and reported three defects; all fixed and re-verified live:

1. **Chips missed nested categories** — `HyprlandKeybinds.categories` walked only top-level sections, so `Window`, `Workspace`, `Virtual machines`, `Session`, `Apps` (one level down in the theme's keybinds.lua) were never offered. Recursive walk now, fixture-proven.
2. **Saves never reached the file** — each save queued behind an async `mkdir` process; the write silently never happened (row visible from memory, gone after the next reload). The `mkdir` runs once at startup and saves now write synchronously in the same event. Verified live: `YTM` created → written (496 bytes) → survived a theme restart.
3. **Leftover empty slab after Cancel/Save** — the form's `Loader` destroyed its item (`active=false hasItem=false`) but kept reporting its last height (measured **660 px**), parking the button and list at the bottom of an empty block. `Layout.preferredHeight` is now pinned to the live item. Verified live: section closed at **600×157** instead of 600×817, user confirmed with 👍.

`[kbd]` breadcrumbs stay in `saveForm`/the write chain as the feature's diagnostics. Gates re-run after the fixes: compile PASS, shell tests 35/2 (both pre-existing), coverage 16 UNMAPPED.

## Done When

- [x] Creating a keybind from the form writes one `hl.bind` line into the marked block, survives `hyprctl reload`, and appears in the manager list, in *Other keybinds* and in the cheatsheet under its category. *(service chain smoke-tested live via `tst_live_smoke`; the form's Save is one `validate → create` call over the same path; cheatsheet parse proven with `get_keybinds.py`)*
- [x] Editing name/category/command/keys updates that line only; deleting removes it; content outside the markers is byte-identical afterwards. *(verified live: update touched only its line, delete left the two hand-written binds byte-identical)*
- [x] Keys render as word caps (`Super`, `Ctrl`, `Shift`, `Enter`, `/`) in the form and in the existing rows. *(`KeyCombos.displayLabel` unit-tested in `tst_keycombos.qml`; both call sites use `StringUtils.keyLabels`)*
- [ ] The form shows `Available` / `Also used by …` for the captured combination *before* Save. *(wired to `repeatUsers`; needs a human eyeball on the live form — not automatable from the CLI)*
- [x] Every form field has a tip; the section header carries its `hint` tooltip.
- [x] Existing shell-shortcut and other-bind rebinding behaves exactly as before. *(the user re-bound a compositor bind live at 08:08 — `keybind_overrides.conf` written through the untouched row flow)*
- [x] All gates: compile PASS, shell tests add no failures, coverage stays at 16 UNMAPPED, icon audit clean, translation count exact. *(1790 → 1814)*
- [x] Committed with conventional messages and pushed to `origin/main`.
