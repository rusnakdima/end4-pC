# Keybind Commands, Reload, and Capture Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `CTRL + SUPER + R` reload the theme, let Settings delete command keybinds, offer a category-driven action picker with a custom command field, and stop existing shortcuts from firing while a new combination is being recorded.

**Architecture:** Extend the existing catalog + overlay + generator system; do not introduce a second command store. A new theme global shortcut calls `GlobalStates.requestShellReload()`. While capture is armed, global-shortcut objects are unloaded (not renamed). Command bind deletion either removes an overlay add or disables a built-in bind. The action picker is derived from catalog command binds and only fills the command field.

**Tech Stack:** QML / Quickshell singletons and settings UI; Python generator + catalog validator; hosted QtTest shell harness.

**Spec:** `docs/superpowers/specs/2026-11-26-keybind-commands-design.md`

## Global Constraints

- `GlobalShortcut` has no `enabled` property, and `name` cannot be changed after registration in Quickshell 0.3.2 — unload shortcuts instead of mutating names.
- Bind ids are byte-stable: keep bind-26's id and the checked-in baseline unchanged; never bless a new baseline.
- Generated bridge names stay `quickshell:runCommand:<id>`; only dispatch kinds listed in `VALID_DISPATCH_KINDS` are valid.
- Overlay authority stays in `ManagedKeybinds.qml`; catalog stays frozen in `defaults/hyprland/keybinds.json`.
- `ShortcutInhibitor` in `Settings.qml` / `Dashboard.qml` stays; capture lock is additive.
- Pre-existing unrelated modified files (`modules/common/Directories.qml`, `modules/common/panels/lock/LockScreen.qml`, `modules/common/widgets/ThumbnailImage.qml`) must not be staged or overwritten.

## Review Focus

- `CTRL + SUPER + R` must call the real reload path, not the old `pgrep -x qs || qs -p ...` no-op — Task 1 generator test asserts the emitted global dispatch and absence of a generated command for bind-26.
- Deleting a user-added command must remove its generated command entry too, not just the Hyprland bind — Task 2 test `test_delete_plan_for_overlay_add` pins `kind === "add"` and the overlay id.
- Deleting a built-in command bind must disable only the bind and keep the command in the picker — Task 2 `test_delete_plan_for_builtin_command` and Task 4 picker test pin this.
- Capture must unregister theme global shortcuts and restore them on stop/timeout/destruction — Task 3 hosted `tst_keybind_capture.qml` checks the gated `active`/`activeShortcutIds`/`globalShortcutsEnabled` properties in both states.
- Selecting a category action must fill only the command; the user's name/category and any later typed command win — Task 4 hosted `tst_keybind_command_actions.qml` asserts `applyAction` does not touch name/category and that `resolveCommand` prefers custom text.

---

### Task 1: Reload shortcut and bind-26 rewrite

**Files:**
- Modify: `GlobalStates.qml` (near `requestShellReload`, line ~122)
- Modify: `defaults/hyprland/keybinds.json` (bind-26, lines 778-793)
- Modify: `tests/shell-tests/state/generated-commands.json` (bind-26 entry, line 32)
- Test: `tests/test_keybind_reload.py` (new)

**Interfaces:**
- Consumes: `GlobalStates.requestShellReload()` (existing void function); `scripts/hyprland/generate_keybinds.py --catalog FILE --commands-out FILE`.
- Produces: global shortcut name `shellReload`; catalog bind-26 with `dispatch.kind === "global"`; no `bind-26` entry in generated commands.

- [ ] **Step 1: Write the failing test**

`tests/test_keybind_reload.py`:

```python
import json, os, subprocess, sys, tempfile, unittest
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "defaults/hyprland/keybinds.json")
GENERATOR = os.path.join(REPO, "scripts/hyprland/generate_keybinds.py")

class KeybindReloadTest(unittest.TestCase):
    def test_bind_26_dispatches_shell_reload(self):
        binds = json.load(open(CATALOG))["binds"]
        bind = next(b for b in binds if b["id"] == "bind-26")
        self.assertEqual(bind["combo"], "CTRL + SUPER + R")
        self.assertEqual(bind["description"], "Shell: Reload theme")
        self.assertEqual(bind["label"], "Shell: Reload theme")
        self.assertEqual(bind["dispatch"], {"kind": "global", "arg": {"kind": "string", "value": "quickshell:shellReload"}})
        self.assertNotIn("command", bind)
        self.assertEqual(bind["code"], 'hl.bind("CTRL + SUPER + R", hl.dsp.global("quickshell:shellReload"), { description = "Shell: Reload theme" })')

    def test_generator_omits_bind_26_command(self):
        with tempfile.TemporaryDirectory() as d:
            commands = os.path.join(d, "commands.json")
            subprocess.run([sys.executable, GENERATOR, "--catalog", CATALOG,
                "--main-out", os.path.join(d, "main.lua"),
                "--custom-out", os.path.join(d, "custom.lua"),
                "--commands-out", commands], check=True, capture_output=True)
            self.assertNotIn("bind-26", json.load(open(commands)))
            self.assertIn("shellReload", open(os.path.join(d, "main.lua")).read())
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest tests.test_keybind_reload -v`
Expected: FAIL on `assertEqual(bind["dispatch"], ...)` (still `kind: "command"`).

- [ ] **Step 3: Rewrite bind-26 and register the shortcut**

Edit bind-26 in `defaults/hyprland/keybinds.json` to the exact values asserted above (keep `id`, `source`, `line`, `category`, `group`, `combo`). Remove the `tests/shell-tests/state/generated-commands.json` `bind-26` entry. Add to `GlobalStates.qml` next to `requestShellReload()`:

```qml
CompositorGlobalShortcut {
    name: "shellReload"
    description: "Reload the theme"
    onPressed: root.requestShellReload()
}
```

`CompositorGlobalShortcut` comes from the already imported `qs.services`.

- [ ] **Step 4: Run tests and validator**

Run: `python3 -m unittest tests.test_keybind_reload -v && python3 scripts/hyprland/validate_keybind_catalog.py`
Expected: 2 tests PASS; validator exits 0 ("catalog ok") without `--bless`.

- [ ] **Step 5: Verify QML and commit**

Run: `./tests/qml-compile-check.sh GlobalStates.qml`
Expected: `PASS: the QML compiles`

Run: `git add GlobalStates.qml defaults/hyprland/keybinds.json tests/shell-tests/state/generated-commands.json tests/test_keybind_reload.py && git commit -m "feat(keybinds): reload theme on CTRL + SUPER + R"`
Expected: one commit.

---

### Task 2: Command bind deletion

**Files:**
- Create: `modules/common/functions/KeybindCommands.js`
- Create: `tests/shell-tests/tst_keybind_commands.qml`
- Modify: `tests/shell-tests/shell.qml` (register the new test file)
- Modify: `modules/ii/settings/pages/KeyboardConfig.qml` (Commands section + `deleteCommandBind`)

**Interfaces:**
- Consumes: `HyprlandKeybinds.effectiveBinds`; `ManagedKeybinds.entryForSource(bind)`; `ManagedKeybinds.remove(id)`; `DisabledKeybinds.disableBinds(id,label,binds)`.
- Produces: `KeybindCommands.commandEntries(binds)` → array of `{bind, id, label, command, combo, description, category}`; `KeybindCommands.deletePlan(bind, entryForSource)` → `{kind:"add"|"builtin", id, label, binds}`; page function `deleteCommandBind(bind) -> bool`.

- [ ] **Step 1: Write the failing tests**

`tests/shell-tests/tst_keybind_commands.qml` (QtQuick + QtTest; import `"modules/common/functions/KeybindCommands.js" as Commands`):

```qml
function test_command_entries_only_include_commands_with_descriptions() {
    const binds = [
        { id: "custom-1", combo: "SUPER + J", description: "Media: Next", dispatch: { kind: "command", command: "playerctl next" } },
        { id: "plain-1", combo: "SUPER + K", description: "Plain", dispatch: { kind: "command" } },
        { id: "shell-1", combo: "SUPER + U", description: "Shell: Reload theme", dispatch: { kind: "global", arg: { value: "quickshell:shellReload" } } }
    ];
    const entries = Commands.commandEntries(binds);
    compare(entries.length, 1);
    compare(entries[0].category, "Media");
    compare(entries[0].label, "Next");
    compare(entries[0].command, "playerctl next");
}

function test_delete_plan_for_overlay_add() {
    const bind = { id: "custom-1", combo: "SUPER + J", description: "Media: Next", dispatch: { kind: "command", command: "playerctl next" } };
    const plan = Commands.deletePlan(bind, () => ({ id: "custom-1" }));
    compare(plan.kind, "add");
    compare(plan.id, "custom-1");
}

function test_delete_plan_for_builtin_command() {
    const bind = { id: "bind-27", sourcePath: "main", line: 70, combo: "SUPER + M", description: "Shell: Open mixer", dispatch: { kind: "command", command: "pavucontrol" } };
    const plan = Commands.deletePlan(bind, () => null);
    compare(plan.kind, "builtin");
    compare(plan.id, "bind-27");
    compare(plan.label, "Shell: Open mixer");
    compare(plan.binds.length, 1);
    compare(plan.binds[0].id, "bind-27");
}
```

Add `"tst_keybind_commands.qml"` to `tests/shell-tests/shell.qml`'s `testFiles` list.

- [ ] **Step 2: Run tests to verify they fail**

Run: `QUICKSHELL_TEST_FILES=tst_keybind_commands.qml ./tests/run-shell-tests.sh`
Expected: FAIL/errors ("Commands is not defined").

- [ ] **Step 3: Implement the helper**

Create `modules/common/functions/KeybindCommands.js` with exactly the two exported functions from Interfaces. `commandEntries` keeps binds whose `dispatch.kind === "command"` and `dispatch.command` is non-empty and whose `description` contains `": "`; category/label are the text before/after the first `": "`. `deletePlan` uses `entryForSource(bind)`; when found, returns `{kind:"add", id: entry.id, label, binds:[bind]}`; otherwise `{kind:"builtin", id: String(bind.id), label: String(bind.description ?? ""), binds:[bind]}`.

- [ ] **Step 4: Implement the Commands section**

In `KeyboardConfig.qml` add `property var commandEntries: KeybindCommands.commandEntries(HyprlandKeybinds.effectiveBinds)` plus a filtered variant using `CF.StringUtils.filterByQueryWithCombos(..., ["label","command","category","description"], ["combo"])`. Add a `ContentSection` titled "Commands" after the main keybind list and before Conflicts, with one row per entry showing label/category/combo/command and a delete icon. Add:

```qml
function deleteCommandBind(bind) {
    const plan = KeybindCommands.deletePlan(bind, b => ManagedKeybinds.entryForSource(b));
    if (plan.kind === "add") {
        const result = ManagedKeybinds.remove(plan.id);
        if (!result.ok) page.captureError = page.formErrorMessage(result.error);
        return result.ok;
    }
    const result = DisabledKeybinds.disableBinds(plan.id, plan.label, plan.binds);
    if (!result.ok) page.captureError = page.formErrorMessage(result.error);
    return result.ok;
}
```

Import `KeybindCommands.js` as `KeybindCommands` beside the other function imports. Ignore `result.ok` only if `KeybindConflicts.writeSucceeded` reports a clean save — use the same gate as the conflict panel.

- [ ] **Step 5: Run tests, compile, commit**

Run: `QUICKSHELL_TEST_FILES=tst_keybind_commands.qml ./tests/run-shell-tests.sh && ./tests/qml-compile-check.sh modules/ii/settings/pages/KeyboardConfig.qml`
Expected: all new tests pass; compile PASS.

Run: `git add modules/common/functions/KeybindCommands.js tests/shell-tests/tst_keybind_commands.qml tests/shell-tests/shell.qml modules/ii/settings/pages/KeyboardConfig.qml && git commit -m "feat(keybinds): delete command keybinds from Settings"`
Expected: one commit.

---

### Task 3: Capture lock by unloading global shortcuts

**Files:**
- Modify: `services/CompositorGlobalShortcut.qml`
- Modify: `services/GeneratedCommandShortcuts.qml`
- Modify: `modules/ii/cheatsheet/Cheatsheet.qml`
- Test: `tests/shell-tests/tst_keybind_capture.qml` (new; register in `shell.qml`)

**Interfaces:**
- Consumes: `GlobalStates.keybindCaptureArmed` (existing bool, set/cleared by `KeyboardConfig.startCapture`/`stopCapture`).
- Produces: `CompositorGlobalShortcut.active` false while armed; `GeneratedCommandShortcuts.activeShortcutIds` empty while armed; `Cheatsheet.globalShortcutsEnabled` false while armed.

- [ ] **Step 1: Write the failing tests**

`tests/shell-tests/tst_keybind_capture.qml`:

```qml
function test_wrapper_is_inactive_while_capturing() {
    GlobalStates.keybindCaptureArmed = false;
    const wrapper = Qt.createComponent("services/CompositorGlobalShortcut.qml").createObject(testCase);
    tryCompare(wrapper, "active", true);
    GlobalStates.keybindCaptureArmed = true;
    tryCompare(wrapper, "active", false);
    GlobalStates.keybindCaptureArmed = false;
    tryCompare(wrapper, "active", true);
    wrapper.destroy();
}

function test_generated_shortcuts_are_unloaded_while_capturing() {
    GlobalStates.keybindCaptureArmed = false;
    verify(GeneratedCommandShortcuts.activeShortcutIds.length > 0);
    GlobalStates.keybindCaptureArmed = true;
    compare(GeneratedCommandShortcuts.activeShortcutIds.length, 0);
    GlobalStates.keybindCaptureArmed = false;
    verify(GeneratedCommandShortcuts.activeShortcutIds.length > 0);
}

function test_cheatsheet_shortcuts_are_disabled_while_capturing() {
    GlobalStates.keybindCaptureArmed = true;
    verify(!Cheatsheet.globalShortcutsEnabled);
    GlobalStates.keybindCaptureArmed = false;
    verify(Cheatsheet.globalShortcutsEnabled);
}
```

Register the file in `shell.qml` and keep the flag false in `cleanup()`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `QUICKSHELL_TEST_FILES=tst_keybind_capture.qml ./tests/run-shell-tests.sh`
Expected: FAIL (`active` stays true; `activeShortcutIds`/`globalShortcutsEnabled` undefined).

- [ ] **Step 3: Gate the three shortcut owners**

- `services/CompositorGlobalShortcut.qml`: add `import qs`, change `active:` to `WM.compositor === "hyprland" && !GlobalStates.keybindCaptureArmed`.
- `services/GeneratedCommandShortcuts.qml`: add `readonly property var activeShortcutIds: GlobalStates.keybindCaptureArmed ? [] : root.shortcutIds`; set `Instantiator.model: root.activeShortcutIds`.
- `modules/ii/cheatsheet/Cheatsheet.qml`: add `import qs`; add `readonly property bool globalShortcutsEnabled: !GlobalStates.keybindCaptureArmed`; wrap each of the three `GlobalShortcut` blocks in a `Loader { active: root.globalShortcutsEnabled; sourceComponent: Component { GlobalShortcut { ... } } }`.

Do not change any shortcut's `name` at runtime.

- [ ] **Step 4: Run tests, compile, commit**

Run: `QUICKSHELL_TEST_FILES=tst_keybind_capture.qml ./tests/run-shell-tests.sh && ./tests/qml-compile-check.sh services/CompositorGlobalShortcut.qml services/GeneratedCommandShortcuts.qml modules/ii/cheatsheet/Cheatsheet.qml`
Expected: all tests pass; compile PASS.

Run: `git add services/CompositorGlobalShortcut.qml services/GeneratedCommandShortcuts.qml modules/ii/cheatsheet/Cheatsheet.qml tests/shell-tests/tst_keybind_capture.qml tests/shell-tests/shell.qml && git commit -m "fix(keybinds): unload global shortcuts while capturing"`
Expected: one commit.

---

### Task 4: Category/action picker in the keybind form

**Files:**
- Modify: `services/HyprlandKeybinds.qml` (after `categories`, line ~195)
- Modify: `modules/ii/settings/pages/KeyboardConfig.qml` (inside `component KeybindForm`)
- Test: `tests/shell-tests/tst_keybind_command_actions.qml` (new; register in `shell.qml`)

**Interfaces:**
- Consumes: `HyprlandKeybinds.effectiveBinds`; `KeybindCommands.commandEntries`.
- Produces: `HyprlandKeybinds.commandActionIndex` → array of `{category, label, command, bindId}`; page helpers `filteredActions(category)` → array and `applyAction(action)` / `resolveCommand()` used by the form.

- [ ] **Step 1: Write the failing tests**

`tests/shell-tests/tst_keybind_command_actions.qml`:

```qml
function test_command_action_index_derives_category_and_label() {
    HyprlandKeybinds.catalog = { binds: [
        { id: "m1", combo: "SUPER + J", description: "Media: Next", dispatch: { kind: "command", command: "playerctl next" } },
        { id: "m2", combo: "SUPER + K", description: "Media: Play/pause", dispatch: { kind: "command", command: "playerctl play-pause" } },
        { id: "s1", combo: "SUPER + M", description: "Shell: Open mixer", dispatch: { kind: "command", command: "pavucontrol" } }
    ] };
    const index = HyprlandKeybinds.commandActionIndex;
    compare(index.length, 3);
    compare(index[0].category, "Media");
    compare(index[0].label, "Next");
    compare(index[0].command, "playerctl next");
    compare(index[2].category, "Shell");
}

function test_picker_selection_fills_only_the_command() {
    const page = pageInstance(); // create from modules/ii/settings/pages/KeyboardConfig.qml
    page.formName = "My key";
    page.formCategory = "Media";
    page.formCommand = "";
    const action = { category: "Media", label: "Next", command: "playerctl next", bindId: "m1" };
    page.applyAction(action);
    compare(page.formCommand, "playerctl next");
    compare(page.formName, "My key");
    compare(page.formCategory, "Media");
    page.formCommand = "custom --flag";
    compare(page.resolveCommand(action), "custom --flag");
    page.destroy();
}
```

Restore `HyprlandKeybinds.catalog` in `cleanup()`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `QUICKSHELL_TEST_FILES=tst_keybind_command_actions.qml ./tests/run-shell-tests.sh`
Expected: FAIL (`commandActionIndex` undefined; `applyAction`/`resolveCommand` undefined).

- [ ] **Step 3: Add the index**

In `services/HyprlandKeybinds.qml`, after `categories`, add `readonly property var commandActionIndex` mapping `root.effectiveBinds` through `KeybindCommands.commandEntries` (import the JS file as `KeybindCommands`), returning `{category, label, command, bindId}`. Dedupe by `command + "\u0000" + label`, preserving catalog order.

- [ ] **Step 4: Add the form pickers**

Inside `component KeybindForm`, before the "App or command" block:
- `readonly property var commandCategories: [...new Set(HyprlandKeybinds.commandActionIndex.map(a => a.category))].sort()`
- `readonly property var filteredActions: page.filteredActions(page.formCategory)`
- a `ConfigComboBox` for categories (`currentValue: page.formCategory`, `onSelected` sets `categoryField.text = newValue`), and one for actions (`currentValue: page.resolveCommand(null)`, `onSelected` calls `page.applyAction(newValue)`).
- Keep the existing custom `commandField` and app picker unchanged and after them; typed text wins.

On the page implement `filteredActions(category)` (empty category = all), `applyAction(action)` (sets `page.formCommand = String(action?.command ?? "")` only), and `resolveCommand(action)` (returns `page.formCommand !== "" ? page.formCommand : String(action?.command ?? "")`). Optionally set the form name from the action label when the name field is still empty; do not overwrite a typed name.

- [ ] **Step 5: Run tests, compile, commit**

Run: `QUICKSHELL_TEST_FILES=tst_keybind_command_actions.qml ./tests/run-shell-tests.sh && ./tests/qml-compile-check.sh services/HyprlandKeybinds.qml modules/ii/settings/pages/KeyboardConfig.qml`
Expected: all tests pass; compile PASS.

Run: `git add services/HyprlandKeybinds.qml modules/ii/settings/pages/KeyboardConfig.qml tests/shell-tests/tst_keybind_command_actions.qml tests/shell-tests/shell.qml && git commit -m "feat(keybinds): pick command actions by category"`
Expected: one commit.

---

### Task 5: Full verification and manual checklist

**Files:** none (verification only; commit only if a fix is needed).

- [ ] **Step 1: Run the offline suites**

Run: `./tests/run-python-tests.sh >/dev/null && ./tests/run-qml-tests.sh > .superpowers/keybind-commands/full.log 2>&1; tail -3 .superpowers/keybind-commands/full.log`
Expected: Python suite green; qmltestrunner green; hosted suite shows only the six known pre-existing environment failures (bar module, appearance, speech-to-text, thumbnail, managed/disabled keybind temp path).

- [ ] **Step 2: Compile every touched QML file**

Run: `./tests/qml-compile-check.sh GlobalStates.qml services/CompositorGlobalShortcut.qml services/GeneratedCommandShortcuts.qml services/HyprlandKeybinds.qml modules/ii/cheatsheet/Cheatsheet.qml modules/ii/settings/pages/KeyboardConfig.qml`
Expected: `PASS: the QML compiles`.

- [ ] **Step 3: Manual checklist in a live Hyprland session after syncing the live config**

1. Press `CTRL + SUPER + R` → theme reloads; Settings shows "Shell: Reload theme" with the same combo.
2. Add a custom command keybind, then delete it from the Commands section → both bind and generated command entry disappear after the generator runs.
3. Delete a built-in command bind (e.g. "Shell: Open mixer") → row disappears; the action is still offered in the picker.
4. In the add form choose Media → Next → command field becomes `playerctl next`; typing a custom command afterwards wins; name/category are not overwritten.
5. Start recording a new shortcut while a bind already exists on that combo → no action fires until capture ends; ShortcutInhibitor still prevents the compositor from acting.
6. Stop capture with Escape and after the 10-second timeout → all global shortcuts return.

- [ ] **Step 4: Commit any fixes found in verification**

Run: `git add <only files you changed> && git commit -m "fix(keybinds): verification followups"`
Expected: one commit only if Step 1-3 exposed a real defect; otherwise skip this step.
