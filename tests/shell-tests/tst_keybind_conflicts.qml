import QtQuick
import QtTest
import "modules/common/functions/KeybindConflicts.js" as Conflicts

/**
 * The pure logic behind the conflicts panel. repeatIndex is a Map of combo ->
 * holders (a repeat is two or more holders), and allUsedCombos is the set of
 * combos the theme already speaks for, including hidden ones. Everything here
 * is a plain value in / value out, so it is tested without a shell service.
 *
 * The expected modifier and key orders are spelled out literally instead of
 * imported from the implementation, so a change to the ordering is caught.
 */
TestCase {
    id: testCase
    name: "KeybindConflicts"
    when: true

    readonly property var modifierOrder: [
        "SUPER", "SUPER + SHIFT", "SUPER + CTRL", "SUPER + ALT",
        "CTRL", "CTRL + SHIFT", "ALT", "ALT + SHIFT"
    ]

    readonly property var keyOrder: [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
    ]

    function holder(id, label, file) {
        return { id: id, label: label, file: file, bind: { action: id } };
    }

    function allCandidateCombos() {
        const out = [];
        for (const mod of testCase.modifierOrder) {
            for (const key of testCase.keyOrder) out.push(mod + " + " + key);
        }
        return out;
    }

    function test_groups_from_map_only_keeps_two_or_more_holders() {
        const index = new Map();
        index.set("SUPER + T", [holder("a", "Terminal", "main"), holder("b", "Console", "custom")]);
        index.set("CTRL + R", [holder("c", "Refresh", "main")]);

        const groups = Conflicts.groupsFrom(index);
        compare(groups.length, 1);
        compare(groups[0].combo, "SUPER + T");
        compare(groups[0].holders.length, 2);
        compare(groups[0].holders[0].id, "a");
        compare(groups[0].holders[0].label, "Terminal");
        compare(groups[0].holders[0].file, "main");
        verify(groups[0].holders[0].bind === undefined, "holders must not carry the underlying bind");
    }

    function test_groups_are_sorted_by_combo() {
        const index = new Map();
        index.set("SUPER + Z", [holder("z1", "Z1", "main"), holder("z2", "Z2", "custom")]);
        index.set("SUPER + A", [holder("a1", "A1", "main"), holder("a2", "A2", "custom")]);
        index.set("CTRL + R", [holder("c1", "C1", "main"), holder("c2", "C2", "custom")]);

        const groups = Conflicts.groupsFrom(index);
        compare(groups.length, 3);
        compare(groups[0].combo, "CTRL + R");
        compare(groups[1].combo, "SUPER + A");
        compare(groups[2].combo, "SUPER + Z");
    }

    function test_groups_from_empty_input() {
        compare(Conflicts.groupsFrom(null).length, 0);
        compare(Conflicts.groupsFrom(new Map()).length, 0);
    }

    function test_choose_keeper_splits_holders() {
        const group = { combo: "SUPER + T", holders: [holder("a", "A", "main"), holder("b", "B", "custom")] };
        const chosen = Conflicts.chooseKeeper(group, "a");
        compare(chosen.keeper.id, "a");
        compare(chosen.others.length, 1);
        compare(chosen.others[0].id, "b");
        compare(chosen.others[0].file, "custom");
    }

    function test_choose_keeper_missing_id_keeps_every_other_holder() {
        const group = { combo: "SUPER + T", holders: [holder("a", "A", "main"), holder("b", "B", "custom")] };
        const chosen = Conflicts.chooseKeeper(group, "not-there");
        verify(chosen.keeper === null || chosen.keeper === undefined, "an unknown keeper id must not pick a holder");
        compare(chosen.others.length, 2);
    }

    function test_suggestion_skips_hidden_and_used() {
        // CTRL + R is a hidden combo in the shipped config. The analyzer does
        // not detect hidden combos itself: it is simply in the supplied used
        // set here, exactly as allUsedCombos would supply it.
        const used = ["SUPER + A", "CTRL + R"];
        const suggestions = Conflicts.freeCombos(used, 3, "SUPER + T");
        compare(suggestions.length, 3);
        // The seed's modifier set is preferred and its first key is taken.
        compare(suggestions[0], "SUPER + B");
        for (const suggestion of suggestions) {
            verify(used.indexOf(suggestion) === -1, "used combo must not be suggested: " + suggestion);
            verify(suggestion !== "CTRL + R", "hidden combo must not be suggested");
        }
    }

    function test_seed_modifier_is_preferred_then_fixed_key_order() {
        const suggestions = Conflicts.freeCombos([], 4, "CTRL + SHIFT + F6");
        compare(suggestions.length, 4);
        compare(suggestions[0], "CTRL + SHIFT + A");
        compare(suggestions[1], "CTRL + SHIFT + B");
        compare(suggestions[2], "CTRL + SHIFT + C");
        compare(suggestions[3], "CTRL + SHIFT + D");
    }

    function test_suggestions_have_mod_plus_key_format() {
        const suggestions = Conflicts.freeCombos(["SUPER + T"], 60, "SUPER + T");
        verify(suggestions.length > 0);
        for (const suggestion of suggestions) {
            const parts = suggestion.split(" + ");
            verify(parts.length >= 2, "combo needs MOD + KEY: " + suggestion);
            const key = parts[parts.length - 1];
            const mods = parts.slice(0, -1).join(" + ");
            verify(testCase.keyOrder.indexOf(key) !== -1, "bad key in suggestion: " + key);
            verify(testCase.modifierOrder.indexOf(mods) !== -1, "bad modifier in suggestion: " + mods);
        }
    }

    function test_zero_available_combos_returns_empty() {
        compare(Conflicts.freeCombos(testCase.allCandidateCombos(), 5, "SUPER + T").length, 0);
        compare(Conflicts.freeCombos([], 0, "SUPER + T").length, 0);
    }

    function test_results_are_stable_across_calls() {
        const used = ["SUPER + A", "CTRL + R", "SUPER + SHIFT + A"];
        const first = Conflicts.freeCombos(used, 12, "SUPER + T");
        const second = Conflicts.freeCombos(used, 12, "SUPER + T");
        compare(JSON.stringify(first), JSON.stringify(second));

        const index = new Map();
        index.set("SUPER + Z", [holder("z1", "Z1", "main"), holder("z2", "Z2", "custom")]);
        index.set("SUPER + A", [holder("a1", "A1", "main"), holder("a2", "A2", "custom")]);
        compare(JSON.stringify(Conflicts.groupsFrom(index)), JSON.stringify(Conflicts.groupsFrom(index)));
    }

    // The fix decision is pure: the caller injects the two services and the
    // entryForSource lookup, so the hosted test can stub both services and
    // verify that a managed holder is moved through ManagedKeybinds.update.
    function test_fix_uses_managed_update_when_managed() {
        const bind = { sourcePath: "/config/hypr/custom/keybinds.lua", line: 12, endLine: 12 };
        const managedHolder = { id: "entry-holder", label: "Panel bind", file: "custom", bind: bind };
        const entry = { id: "entry-42", line: 12, endLine: 12 };

        let managedCall = null;
        let overrideCall = null;
        let lookupArg = null;
        const managed = { update: (id, fields) => { managedCall = { id: id, fields: fields }; } };
        const overrides = { setOverride: (id, combo) => { overrideCall = { id: id, combo: combo }; } };
        const lookup = b => { lookupArg = b; return b === bind ? entry : null; };

        const service = Conflicts.fixHolder(managedHolder, "SUPER + B", lookup, managed, overrides);

        compare(service.kind, "managed");
        verify(service.ok, "a successful managed write must report ok");
        verify(lookupArg === bind, "the lookup must receive the holder's bind");
        verify(managedCall !== null, "managed.update was not called for a managed bind");
        compare(managedCall.id, "entry-42");
        compare(managedCall.fields.combo, "SUPER + B");
        verify(Object.prototype.hasOwnProperty.call(managedCall.fields, "combo"),
            "update must be called with {combo}");
        verify(overrideCall === null, "setOverride must not be called for a managed bind");
    }

    // A plain bind (action === "") is not a shell action. Its repeatIndex
    // holder is shaped like this in production: a NUL-separated self-exclusion
    // id, a bare overrideId (the key the overrides file actually uses), a
    // per-line uid, and the underlying bind. No idealized clean ids here.
    function realisticPlainHolder(combo, line) {
        const overrideId = "bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_");
        return {
            id: "main\u0000" + overrideId,
            uid: "main\u0000" + String(line) + "\u0000" + overrideId,
            overrideId: overrideId,
            label: "Plain bind on line " + line,
            file: "main",
            bind: {
                sourcePath: "/config/hypr/hyprland/keybinds.lua",
                line: line, endLine: line, action: "",
                mods: ["SUPER"], key: "T"
            }
        };
    }

    function test_fix_uses_the_bare_override_id_for_a_plain_bind() {
        const combo = "SUPER + T";
        const holder = testCase.realisticPlainHolder(combo, 30);
        verify(holder.id.indexOf("\u0000") !== -1, "the fixture must use the real NUL id");

        let overrideCall = null;
        const overrides = { setOverride: (id, c) => { overrideCall = { id: id, combo: c }; } };
        const managed = { update: () => { throw new Error("a plain bind is not managed"); } };

        const service = Conflicts.fixHolder(holder, "SUPER + B", () => null, managed, overrides);
        compare(service.kind, "override");
        verify(service.ok, "a successful override write must report ok");
        verify(overrideCall !== null, "setOverride was not called");
        compare(overrideCall.id, holder.overrideId);
        compare(overrideCall.id, "bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_"));
        verify(overrideCall.id.indexOf("\u0000") === -1,
            "no NUL may reach keybind_overrides.conf");
        compare(overrideCall.combo, "SUPER + B");
    }

    function test_two_same_file_plain_binds_on_one_combo_get_two_distinct_moves() {
        const combo = "SUPER + T";
        const expectedId = "bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_");
        const index = new Map();
        index.set(combo, [testCase.realisticPlainHolder(combo, 10), testCase.realisticPlainHolder(combo, 20)]);

        const groups = Conflicts.groupsFrom(index);
        compare(groups.length, 1);
        const holders = groups[0].holders;
        compare(holders.length, 2, "both plain binds must be shown as holders");
        compare(holders[0].id, holders[1].id, "the repeatUsers self-exclusion id stays shared");
        verify(holders[0].uid !== holders[1].uid, "uid must separate the two binds");
        for (const holder of holders) {
            compare(holder.overrideId, expectedId, "the bare override key must survive projection");
            verify(holder.id.indexOf("\u0000") !== -1, "the NUL id must survive projection");
        }

        const originals = index.get(combo);
        const moves = [];
        const overrides = { setOverride: (id, c) => { moves.push({ id: id, combo: c }); } };
        const managed = { update: () => { throw new Error("plain binds are not managed"); } };

        // Keep either one: the other is a single, independent Move action.
        for (const keeper of holders) {
            const chosen = Conflicts.chooseKeeper(groups[0], keeper.uid);
            compare(chosen.keeper.uid, keeper.uid);
            compare(chosen.others.length, 1,
                "each keeper must leave exactly one other holder to move");
            const original = originals.find(h => Conflicts.identityOf(h) === Conflicts.identityOf(chosen.others[0]));
            verify(original !== undefined, "the projected holder must map back to its real holder");
            compare(Conflicts.fixHolder(original, "SUPER + B", () => null, managed, overrides).kind, "override");
        }

        compare(moves.length, 2, "two keepers mean two Move actions, not an empty list");
        for (const move of moves) {
            compare(move.id, expectedId);
            verify(move.id.indexOf("\u0000") === -1, "no NUL may reach keybind_overrides.conf");
            compare(move.combo, "SUPER + B");
        }
    }

    function test_fix_uses_override_when_not_managed() {
        const bind = { sourcePath: "/config/hypr/hyprland/keybinds.lua", line: 30, endLine: 30 };
        const plainHolder = { id: "terminal", label: "Terminal", file: "main", bind: bind };

        let managedCall = null;
        let overrideCall = null;
        const managed = { update: (id, fields) => { managedCall = { id: id, fields: fields }; } };
        const overrides = { setOverride: (id, combo) => { overrideCall = { id: id, combo: combo }; } };
        const lookup = b => null;

        const service = Conflicts.fixHolder(plainHolder, "SUPER + C", lookup, managed, overrides);

        compare(service.kind, "override");
        verify(service.ok, "a successful override write must report ok");
        verify(overrideCall !== null, "setOverride was not called for a non-managed bind");
        compare(overrideCall.id, "terminal");
        compare(overrideCall.combo, "SUPER + C");
        verify(managedCall === null, "managed.update must not be called for a non-managed bind");
    }

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

    function test_alias_holders_have_readable_labels_when_binds_have_no_comment() {
        const aliasIndex = new Map();
        aliasIndex.set("sidebarLeftToggle", {
            action: "sidebarLeftToggle",
            label: "Toggle left sidebar",
            combos: [
                { combo: "SUPER + A", bind: { id: "bind-6", comment: "Toggle left sidebar" } },
                { combo: "SUPER + B", bind: { id: "bind-8", comment: "" } },
                { combo: "SUPER + O", bind: { id: "bind-9", comment: "" } }
            ]
        });
        const groups = Conflicts.groupsFrom(new Map(), aliasIndex);
        compare(groups.length, 1);
        // Every row must be nameable: an empty catalog comment falls back to
        // the action label instead of producing a blank keeper row.
        for (const holder of groups[0].holders)
            verify(holder.label !== "", "alias holder " + holder.combo + " has no label");
        compare(groups[0].holders[1].label, "Toggle left sidebar");
        compare(groups[0].holders[1].combo, "SUPER + B");
        compare(groups[0].holders[2].combo, "SUPER + O");
    }

    function test_target_holder_uses_the_conflicting_combo_not_the_primary_bind() {
        const group = { kind: "combo", combo: "SUPER + B", holders: [] };
        const holder = { id: "sidebarLeftToggle", bind: { id: "bind-6", mods: ["SUPER"], key: "A" } };
        const actionData = {
            action: "sidebarLeftToggle",
            binds: [
                { id: "bind-6", mods: ["SUPER"], key: "A" },
                { id: "bind-8", mods: ["SUPER"], key: "B" },
                { id: "bind-9", mods: ["SUPER"], key: "O" }
            ]
        };
        const comboOf = bind => ["SUPER", ...(bind.mods ?? []).filter(m => m !== "SUPER")].join(" + ") + " + " + bind.key;
        const target = Conflicts.targetHolder(group, holder, actionData, comboOf);
        compare(target.bind.id, "bind-8");
        compare(target.overrideId, "bind-8");
        // The input holder is not mutated.
        compare(holder.bind.id, "bind-6");
    }

    function test_write_succeeded_requires_a_clean_save() {
        verify(Conflicts.writeSucceeded({ ok: true, error: "" }, ""));
        verify(Conflicts.writeSucceeded(null, ""));
        verify(!Conflicts.writeSucceeded({ ok: true, error: "" }, "disk full"));
        verify(!Conflicts.writeSucceeded({ ok: false, error: "not-loaded" }, ""));
    }

    function test_fix_holder_reports_service_failure() {
        const holder = { id: "a", overrideId: "bind_x" };
        const managed = { update: () => ({ ok: false, error: "write-failed" }) };
        const result = Conflicts.fixHolder(holder, "SUPER + B", () => ({ id: "a" }), managed, {});
        compare(result.ok, false);
        compare(result.error, "write-failed");
    }
}
