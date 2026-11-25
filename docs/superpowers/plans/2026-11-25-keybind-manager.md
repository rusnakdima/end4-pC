# Keybind Manager Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Settings → Keyboard capture any chord, delete and resolve keybinds reliably, search by key combination, and warn about both duplicate-combo and alias conflicts.

**Architecture:** Add a `ShortcutInhibitor` to both settings windows while a capture is armed, a canonical combo parser/matcher used by capture fallback and search, an alias index feeding a two-kind conflict model, and per-combo delete handling. All writes stay in `ManagedKeybinds` / `DisabledKeybinds` with `result.ok` checks.

**Tech Stack:** QML, plain JavaScript modules, Quickshell (`GlobalShortcut`, `ShortcutInhibitor`), Hyprland overlay JSON.

**Spec:** `docs/superpowers/specs/2026-11-25-keybind-manager-design.md`

## Global Constraints

- Overlay path: `~/.config/hypr/custom/keybind-overlay.json`.
- Catalog binds are frozen; user changes go to overlay `overrides`, `adds` or `disabled`.
- Raw Lua binds are never editable.
- Every service write checks `result.ok` and surfaces `result.error`.
- Tests: `./tests/run-qml-tests.sh` (pure modules + hosted shell tests) must pass.

## Review Focus

- A chord bound to a compositor shortcut must still be captured while armed; if the inhibitor is inactive the user must be told and be able to type the combo.
- Removing one alias of an action must leave the action's other combos working and be restorable from Deleted keybinds.
- A failed overlay write must not be reported as "Conflicts resolved".
- Pressed-combo search must not filter out every row because of separator or case differences.
- Raw Lua rows must never gain a delete or capture affordance that promises a write.

---

### Task 1: Combo parsing, canonical matching, combo-aware filter

**Files:**
- Modify: `modules/common/functions/KeyCombos.js`
- Modify: `modules/common/functions/StringUtils.qml:315-327`
- Test: `modules/common/functions/tst_keycombos.qml`
- Test: `tests/shell-tests/tst_strings.qml:170-216`

**Interfaces:**
- Produces: `KeyCombos.comboFromText(text) -> string` (canonical `"SUPER + I"`, `""` when no key token)
- Produces: `KeyCombos.canonicalCombo(text) -> string` (lowercase, modifiers in `CTRL, SUPER, SHIFT, ALT` order, joined by `+`)
- Produces: `KeyCombos.comboMatches(query, combo) -> bool`
- Produces: `StringUtils.comboFromText(text) -> string`
- Produces: `StringUtils.filterByQueryWithCombos(items, query, keys, comboKeys) -> Array`

- [ ] **Step 1: Write failing parser tests**

In `tst_keycombos.qml` add:

```qml
function test_combo_from_text_accepts_any_spelling() {
    compare(KeyCombos.comboFromText("super+i"), "SUPER + I");
    compare(KeyCombos.comboFromText("Super + I"), "SUPER + I");
    compare(KeyCombos.comboFromText("i super"), "SUPER + I");
    compare(KeyCombos.comboFromText("ctrl shift k"), "CTRL + SHIFT + K");
    compare(KeyCombos.comboFromText(""), "");
    compare(KeyCombos.comboFromText("shift"), "");
}

function test_canonical_combo_ignores_order_case_and_separators() {
    compare(KeyCombos.canonicalCombo("SUPER + I"), "super+i");
    compare(KeyCombos.canonicalCombo("i + super"), "super+i");
    verify(KeyCombos.comboMatches("super i", "SUPER + I"));
    verify(!KeyCombos.comboMatches("super o", "SUPER + I"));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input modules/common/functions -functions`
Expected: FAIL, `comboFromText is not a function`.

- [ ] **Step 3: Implement parser in `KeyCombos.js`**

Add `MODIFIER_TOKENS` (`super`, `meta`→`super`, `ctrl`, `control`→`ctrl`, `shift`, `alt`), `canonicalCombo(text)`, `comboFromText(text)` and `comboMatches(query, combo)`. `canonicalCombo` splits on non-alphanumerics, deduplicates modifiers and orders them `CTRL, SUPER, SHIFT, ALT`, then appends remaining key tokens in input order. `comboFromText` returns `""` unless exactly one non-modifier key token exists, and upper-cases single-character keys.

- [ ] **Step 4: Write failing filter tests**

In `tst_strings.qml` add:

```qml
function test_filter_by_query_with_combos_matches_pressed_and_typed_combos() {
    const items = [
        { name: "Terminal", combo: "SUPER + Return" },
        { name: "Sidebar", combo: "SUPER + B" },
        { name: "Settings", combo: "SUPER + I" }
    ];
    compare(StringUtils.filterByQueryWithCombos(items, "super+i", ["name"], ["combo"]).length, 1);
    compare(StringUtils.filterByQueryWithCombos(items, "SUPER + I", ["name"], ["combo"])[0].name, "Settings");
    compare(StringUtils.filterByQueryWithCombos(items, "super", ["name"], ["combo"]).length, 3);
    compare(StringUtils.filterByQueryWithCombos(items, "terminal", ["name"], ["combo"]).length, 1);
    compare(StringUtils.filterByQueryWithCombos(items, "", ["name"], ["combo"]).length, 3);
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `./tests/run-shell-tests.sh`
Expected: FAIL, `filterByQueryWithCombos is not a function`.

- [ ] **Step 6: Implement the filter**

In `StringUtils.qml` add `comboFromText` (delegates to `KeyCombos.comboFromText`) and `filterByQueryWithCombos`. Empty query returns the input untouched. If any `comboKeys` value canonicalises exactly to the canonical whole query, return items whose combo also matches exactly. Otherwise keep the existing per-token behaviour, accepting a token when a text key contains it or a combo key's canonical form contains the canonical token. Array combo values are joined with spaces before canonicalising.

- [ ] **Step 7: Run both test stages**

Run: `./tests/run-qml-tests.sh`
Expected: `SHELL_TEST_RESULT` with `failed=0`, and no qmltestrunner failures.

- [ ] **Step 8: Commit**

```bash
git add modules/common/functions/KeyCombos.js modules/common/functions/StringUtils.qml modules/common/functions/tst_keycombos.qml tests/shell-tests/tst_strings.qml
git commit -m "feat(keybinds): parse and match key combinations canonically"
```

---

### Task 2: Capture inhibitor and typed fallback

**Files:**
- Modify: `GlobalStates.qml:54` (near `keybindFilter`)
- Modify: `modules/ii/settings/Settings.qml:4-14,38-78`
- Modify: `modules/ii/settings/Dashboard.qml:1-45`
- Modify: `modules/ii/settings/pages/KeyboardConfig.qml:366-419, 2283-2372`
- Test: manual plus existing capture tests

**Interfaces:**
- Produces: `GlobalStates.keybindCaptureArmed: bool`
- Produces: `GlobalStates.keybindCaptureInhibited: bool`
- Consumes: `KeyCombos.comboFromText`

- [ ] **Step 1: Add the global flags**

In `GlobalStates.qml` add `property bool keybindCaptureArmed: false` and `property bool keybindCaptureInhibited: false` beside `keybindFilter`.

- [ ] **Step 2: Attach the inhibitor in both windows**

In `Settings.qml` add `import Quickshell.Wayland`. Inside the `FloatingWindow` (`id: window`) add:

```qml
Loader {
    active: WM.compositor === "hyprland"
    sourceComponent: ShortcutInhibitor {
        window: window
        enabled: GlobalStates.keybindCaptureArmed
        onActiveChanged: GlobalStates.keybindCaptureInhibited = active
    }
}
```

Do the same inside `Dashboard.qml`'s `FloatingWindow`.

- [ ] **Step 3: Arm and disarm from the page**

In `startCapture`, after setting `page.capturing`, set `GlobalStates.keybindCaptureArmed = true` and `GlobalStates.keybindCaptureInhibited = false`. In `stopCapture`, set both back to `false`. Add `Component.onDestruction: page.stopCapture()` if the page has no destruction handler.

- [ ] **Step 4: Add the typed fallback**

Below the keys box in `KeybindForm` add a `MaterialTextField` (`id: comboTextField`, placeholder `Translation.tr("Or type: SUPER + I")`) and a `DialogButton` "Use" that sets `page.formCombo = CF.StringUtils.comboFromText(comboTextField.text)`, clears `page.formError`, and calls `page.stopCapture()` when the parse is non-empty.

- [ ] **Step 5: Show the inhibitor hint**

In the form, under the keys box, show a `StyledText` when `page.capturing === "form" && !GlobalStates.keybindCaptureInhibited` with text `Translation.tr("The compositor is still holding this shortcut. Type the combination below instead.")` in `page.conflictColor`.

- [ ] **Step 6: Manual verification**

Run the shell, open Settings → Keyboard, start editing a bind and press SUPER+I (the settings toggle). Expected: the capture shows `SUPER + I` instead of closing Settings. Press Escape: capture stops, Settings stays open.

- [ ] **Step 7: Commit**

```bash
git add GlobalStates.qml modules/ii/settings/Settings.qml modules/ii/settings/Dashboard.qml modules/ii/settings/pages/KeyboardConfig.qml
git commit -m "feat(keybinds): capture chords inhibited from the compositor"
```

---

### Task 3: Search by pressed or typed key combination

**Files:**
- Modify: `modules/ii/settings/pages/KeyboardConfig.qml:57-94, 425-464, 827-863`
- Test: covered by Task 1 filter tests plus manual check

**Interfaces:**
- Consumes: `StringUtils.filterByQueryWithCombos`
- Consumes: `page.startCapture("search")`

- [ ] **Step 1: Switch the filters to combo-aware matching**

Replace the `visibleManaged`, `visibleShell`, `visibleSeries` and `filterOtherSections` calls with `filterByQueryWithCombos`. Pass combo fields: managed `["combo"]`, shell `["combos"]`, other `["searchCombo"]`; series keeps `filterByQuery` (labels and mods only).

- [ ] **Step 2: Add the search capture button**

Beside the clear button in the search row add an `IconToolbarButton` with `text: "keyboard"` and tooltip `Translation.tr("Search by key combination")`, calling `page.startCapture("search")`.

- [ ] **Step 3: Handle the search capture**

In `handleCapturedKey`, before the `"form"` branch, add:

```qml
if (page.capturing === "search") {
    GlobalStates.keybindFilter = combo;
    page.stopCapture();
    return true;
}
```

- [ ] **Step 4: Manual verification**

Type `super+i`: Settings row appears. Clear, click the keyboard button, press SUPER+B: filter becomes `SUPER + B` and only rows using it remain. Escape cancels the search capture.

- [ ] **Step 5: Commit**

```bash
git add modules/ii/settings/pages/KeyboardConfig.qml
git commit -m "feat(keybinds): search by pressed or typed combination"
```

---

### Task 4: Alias index and two-kind conflict model

**Files:**
- Modify: `services/HyprlandKeybinds.qml:197-217` (after `shellActions`)
- Modify: `modules/common/functions/KeybindConflicts.js`
- Test: `tests/shell-tests/tst_keybind_conflicts.qml`

**Interfaces:**
- Produces: `HyprlandKeybinds.aliasIndex: Map<string, {action, label, combos: [{combo, bind}]}>`, only actions with two or more combos
- Produces: `KeybindConflicts.groupsFrom(repeatIndex, aliasIndex)` returning groups with `{kind: "combo"|"alias", combo, action, label, holders}`; holders gain `combo`
- Produces: `KeybindConflicts.removalPlan(group, keeperId) -> {kind, keeper, remove}`
- Changes: `KeybindConflicts.fixHolder(...) -> {kind: "managed"|"override", ok: bool, error: string}`

- [ ] **Step 1: Write failing tests**

In `tst_keybind_conflicts.qml` add:

```qml
function test_alias_index_builds_an_alias_group() {
    const aliasIndex = new Map();
    aliasIndex.set("sidebarLeftToggle", {
        action: "sidebarLeftToggle",
        label: "Toggle left sidebar",
        combos: [
            { combo: "SUPER + A", bind: { id: "bind-6" } },
            { combo: "SUPER + B", bind: { id: "bind-8" } },
            { combo: "SUPER + O", bind: { id: "bind-9" } }
        ]
    });
    const groups = Conflicts.groupsFrom(new Map(), aliasIndex);
    compare(groups.length, 1);
    compare(groups[0].kind, "alias");
    compare(groups[0].holders.length, 3);
    compare(groups[0].holders[1].combo, "SUPER + B");
    compare(groups[0].holders[1].uid, "sidebarLeftToggle\u0000SUPER + B");
}

function test_removal_plan_keeps_one_alias() {
    const aliasGroup = {
        kind: "alias", combo: "SUPER + A", action: "sidebarLeftToggle",
        holders: [
            { id: "sidebarLeftToggle", uid: "sidebarLeftToggle\u0000SUPER + A", combo: "SUPER + A" },
            { id: "sidebarLeftToggle", uid: "sidebarLeftToggle\u0000SUPER + B", combo: "SUPER + B" }
        ]
    };
    const plan = Conflicts.removalPlan(aliasGroup, "sidebarLeftToggle\u0000SUPER + B");
    compare(plan.keeper.combo, "SUPER + B");
    compare(plan.remove.length, 1);
    compare(plan.remove[0].combo, "SUPER + A");
}

function test_fix_holder_reports_service_failure() {
    const holder = { id: "a", overrideId: "bind_x" };
    const managed = { update: () => ({ ok: false, error: "write-failed" }) };
    const result = Conflicts.fixHolder(holder, "SUPER + B", () => ({ id: "a" }), managed, {});
    compare(result.ok, false);
    compare(result.error, "write-failed");
}
```

Update the existing `fixHolder` assertions to compare `.kind` (and `.ok`).

- [ ] **Step 2: Run to verify they fail**

Run: `./tests/run-shell-tests.sh`
Expected: FAIL on `groupsFrom` alias kind / `removalPlan`.

- [ ] **Step 3: Add `aliasIndex`**

In `HyprlandKeybinds.qml`, after `shellActions`:

```qml
readonly property var aliasIndex: {
    const index = new Map();
    for (const entry of root.shellActions) {
        if ((entry.combos ?? []).length < 2) continue;
        index.set(entry.action, {
            action: entry.action,
            label: entry.description !== "" ? entry.description : entry.action,
            combos: entry.combos.map(combo => ({
                combo: combo,
                bind: entry.binds.find(bind => root.comboOf(bind) === combo)
            }))
        });
    }
    return index;
}
```

- [ ] **Step 4: Extend `KeybindConflicts.js`**

`project` keeps `combo` and, for alias holders, `uid`. `groupsFrom(repeatIndex, aliasIndex)` appends alias groups after combo groups: each holder `{id: action, uid: action + "\u0000" + combo, combo, label, file: "shell", catalogIds: [bind.id]}`. Add `removalPlan(group, keeperId)` using `chooseKeeper`. Change `fixHolder` to capture the service result and return `{kind, ok, error}`.

- [ ] **Step 5: Run tests**

Run: `./tests/run-shell-tests.sh`
Expected: `failed=0`.

- [ ] **Step 6: Commit**

```bash
git add services/HyprlandKeybinds.qml modules/common/functions/KeybindConflicts.js tests/shell-tests/tst_keybind_conflicts.qml
git commit -m "feat(keybinds): model one-action-many-combos conflicts"
```

---

### Task 5: Resolve conflicts by keeping one or applying offers

**Files:**
- Modify: `modules/ii/settings/pages/KeyboardConfig.qml:130, 152-176, 1165-1370`
- Test: manual plus Task 4 unit tests

**Interfaces:**
- Consumes: `KeybindConflicts.groupsFrom(HyprlandKeybinds.repeatIndex, HyprlandKeybinds.aliasIndex)`
- Produces: `page.removeConflictOthers(group, keeperId) -> bool`
- Produces: `page.applyConflictOffers(group) -> bool`
- Produces: `page.deleteAliasCombo(actionData, combo) -> bool`

- [ ] **Step 1: Feed alias groups to the panel**

Change `conflictGroups` to pass `HyprlandKeybinds.aliasIndex`. The panel heading uses `group.kind === "alias" ? "Bound to %1 combinations" : "Used by %1 bindings"`.

- [ ] **Step 2: Add removal and offer helpers**

Add page functions:

- `deleteAliasCombo(actionData, combo)`: find the bind via `HyprlandKeybinds.comboOf`, call `DisabledKeybinds.disableBinds("shell:" + action + ":" + combo, label, [bind])`, set `captureError` on failure, return `ok`.
- `removeConflictOthers(group, keeperId)`: use `KeybindConflicts.removalPlan`; for each removed holder resolve the live holder with `originalConflictHolder`; overlay adds use `ManagedKeybinds.remove`, anything with an action uses `deleteAliasCombo`, plain binds use `DisabledKeybinds.disableBinds("bind:" + file + ":" + line, label, [bind])`. Only set `conflictResolved` when every call returned ok.
- `applyConflictOffers(group)`: `freeCombos(allUsedCombos, others.length, group.combo)`; error when there are not enough suggestions; call `moveConflictHolder` for each with the matching suggestion and require every result to be ok.

- [ ] **Step 3: Check every fix result**

`moveConflictHolder` reads `KeybindConflicts.fixHolder(...).ok`; on failure set `captureError` from `formErrorMessage(error)` and do not set `conflictResolved`.

- [ ] **Step 4: Add panel actions**

At the bottom of `ConflictGroupPanel` add two `DialogButton`s: "Use only this one" (calls `page.removeConflictOthers(modelData, panel.keeperId)`) and, for `kind === "combo"`, "Apply suggested keys to all others" (calls `page.applyConflictOffers(modelData)`). Hide the per-holder Move section and suggestions for alias groups.

- [ ] **Step 5: Manual verification**

With the default three-combo sidebar action, the Conflicts section lists a `sidebarLeftToggle` alias group. "Use only this one" on SUPER+B removes SUPER+A and SUPER+O, leaves SUPER+B working, and both removed combos appear in Deleted keybinds. A duplicate-combo group still supports Move and Apply offers, and a simulated write failure shows an error rather than "Conflicts resolved".

- [ ] **Step 6: Commit**

```bash
git add modules/ii/settings/pages/KeyboardConfig.qml
git commit -m "feat(keybinds): resolve conflicts by keeping one or applying offers"
```

---

### Task 6: Reliable delete, including one alias

**Files:**
- Modify: `modules/ii/settings/pages/KeyboardConfig.qml:1373-1535, 2003-2135`
- Test: manual

**Interfaces:**
- Consumes: `page.deleteAliasCombo`

- [ ] **Step 1: Per-alias delete affordance**

Replace the plain alias text in `ShortcutRow` with a `Repeater` over `actionData.binds.filter(bind => HyprlandKeybinds.comboOf(bind) !== shortcutRow.combo)`. Each row shows the combo (amber, warning icon) and a delete `MaterialSymbol` when `!DisabledKeybinds.isDisabled("shell:" + action + ":" + combo)`; clicking calls `page.deleteAliasCombo`.

- [ ] **Step 2: Check managed delete results**

In `ManagedRow` change the delete click to:

```qml
onClicked: {
    const result = ManagedKeybinds.remove(managedRow.entry.id);
    if (!result.ok) page.captureError = page.formErrorMessage(result.error);
}
```

- [ ] **Step 3: Keep raw rows uneditable**

Verify `deleteEnabled` is false for raw binds and that no alias delete appears for a raw action; the existing `raw` guard stays.

- [ ] **Step 4: Manual verification**

Delete SUPER+B from the sidebar row; SUPER+A and SUPER+O remain, SUPER+B appears under Deleted keybinds and restore brings it back. Delete an overlay add: the row disappears; delete a plain catalog bind: it is recoverable.

- [ ] **Step 5: Commit**

```bash
git add modules/ii/settings/pages/KeyboardConfig.qml
git commit -m "fix(keybinds): delete single alias combos and report failures"
```

---

### Task 7: Warning styling for both conflict kinds

**Files:**
- Modify: `modules/ii/settings/pages/KeyboardConfig.qml:1406-1450, 1838-1870, 2028-2066, 2346-2355`
- Test: manual

**Interfaces:**
- Produces: per-row `conflicted` boolean (repeats or aliases)

- [ ] **Step 1: Shortcut rows**

Add `aliasConflict: aliases.length > 0` and `conflicted: repeats.length > 0 || aliasConflict`. Set `border.width: capturing || conflicted ? 1 : 0` and `border.color: capturing ? primary : conflictColor`. Add a `MaterialSymbol` "warning" in `conflictColor` beside the title when `conflicted`. Render the alias line in `conflictColor` with a warning icon.

- [ ] **Step 2: Other and managed rows**

Add the same border and warning icon when `repeats.length > 0`. Keep the amber repeat sentence.

- [ ] **Step 3: Form warning**

Add a warning `MaterialSymbol` next to the form's repeat sentence.

- [ ] **Step 4: Manual verification**

The sidebar row shows a warning icon and accent border because it has aliases. A duplicate combo row shows the same. Colors stay readable in light and dark mode.

- [ ] **Step 5: Commit**

```bash
git add modules/ii/settings/pages/KeyboardConfig.qml
git commit -m "feat(keybinds): mark both conflict kinds as warnings"
```

---

### Task 8: Full verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run all tests**

Run: `./tests/run-qml-tests.sh`
Expected: exit 0, hosted summary `failed=0`.

- [ ] **Step 2: Lint/compile the touched QML**

Run: `./tests/qml-compile-check.sh` if it accepts file arguments; otherwise `qmllint` on the modified files.
Expected: no new errors.

- [ ] **Step 3: Manual checklist**

- SUPER+I captured while Settings is open.
- Typed fallback sets `SUPER + I`.
- Search by typed `super+i` and by pressed SUPER+B.
- Delete one alias; restore it from Deleted keybinds.
- Use-only-this on a duplicate combo removes all others.
- Apply suggested keys to all others moves each holder.
- Failed write shows an error and does not say resolved.
- Warning icons and borders appear for both conflict kinds.

- [ ] **Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "test(keybinds): verify capture, delete, conflicts and search"
```
