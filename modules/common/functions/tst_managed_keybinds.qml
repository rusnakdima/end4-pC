import QtQuick
import QtTest
import "KeybindStore.js" as KeybindStore

/**
 * The write path of the keybind manager is now a JSON overlay, not a Lua
 * managed block: the settings form writes adds/overrides/disabled to
 * ~/.config/hypr/custom/keybind-overlay.json, and the generator merges that
 * overlay with the frozen catalog from defaults/hyprland/keybinds.json.
 *
 * This test exercises the pure JavaScript half of that path: makeAdd /
 * withAdds / withOverrides / comboOverride build the overlay, renderOverlay
 * turns it into the on-disk JSON, parseOverlay reads it back, and
 * effectiveBinds produces the merged list the panel and Hyprland consume.
 * The whole round-trip is in memory, so no path is ever written: the real
 * overlay is never touched and no generator is invoked. (That is stricter
 * than using a temp path, and keeps this a qmltestrunner-only test — the
 * hosted singleton IO is covered by tests/shell-tests.)
 */
TestCase {
    id: root
    name: "ManagedKeybinds"
    when: true

    // --- helpers ---------------------------------------------------------------

    function addEntry(id, name, category, command, combo) {
        return { id: id, name: name, category: category, command: command, combo: combo };
    }

    function catalogBind(id, combo, description, category) {
        return {
            id: id,
            combo: combo,
            description: description,
            category: category,
            dispatch: { kind: "command", id: id, command: "cmd-" + id },
            options: { locked: true },
            source: "main",
            line: 42,
            code: "frozen code for " + id
        };
    }

    function sampleCatalog() {
        return { binds: [
            catalogBind("cat-a", "SUPER + A", "Alpha", "Apps"),
            catalogBind("cat-b", "SUPER + B", "Beta", "Apps"),
            catalogBind("cat-c", "XF86AudioPlay", "Play", "Media")
        ] };
    }

    // Compare by JSON so a field added to one side but not the other fails,
    // instead of QtTest's shallow compare of two JS objects.
    function sameJson(actual, expected, message) {
        compare(JSON.stringify(actual), JSON.stringify(expected), message);
    }

    // Build the next overlay the same way ManagedKeybinds.create() does.
    function createAdd(overlay, id, entry) {
        const next = Object.assign({}, entry, { id: id });
        const add = KeybindStore.makeAdd(next, id);
        return { add: add, overlay: KeybindStore.withAdds(overlay, (overlay.adds ?? []).concat([add])) };
    }

    // --- overlay skeleton ------------------------------------------------------

    function test_new_overlay_starts_with_three_empty_sections() {
        sameJson(KeybindStore.newOverlay(), { overrides: {}, adds: [], disabled: [] });
        compare(KeybindStore.OVERLAY_DEFAULT.adds.length, 0);
    }

    function test_parse_overlay_accepts_empty_and_broken_text() {
        const empty = KeybindStore.newOverlay();
        sameJson(KeybindStore.parseOverlay(""), empty, "empty text must fall back to an empty overlay");
        sameJson(KeybindStore.parseOverlay("   \n"), empty, "whitespace must fall back to an empty overlay");
        sameJson(KeybindStore.parseOverlay(undefined), empty, "undefined must fall back to an empty overlay");
        sameJson(KeybindStore.parseOverlay("{ not json"), empty, "broken JSON must fall back to an empty overlay");
        sameJson(KeybindStore.parseOverlay("[]"), empty, "an array is not an overlay");
        sameJson(KeybindStore.parseOverlay("null"), empty, "null is not an overlay");
    }

    function test_parse_overlay_keeps_only_recognised_sections() {
        const text = JSON.stringify({
            overrides: { "cat-a": { combo: "SUPER + Z" } },
            adds: [{ id: "one", combo: "F9" }],
            disabled: ["cat-b"],
            unknown: "ignored"
        });
        const parsed = KeybindStore.parseOverlay(text);
        compare(Object.keys(parsed).length, 3, "unknown sections must be dropped");
        compare(parsed.overrides["cat-a"].combo, "SUPER + Z");
        compare(parsed.adds.length, 1);
        compare(parsed.disabled[0], "cat-b");

        const partial = KeybindStore.parseOverlay('{ "adds": [ { "id": "one" } ] }');
        sameJson(partial.overrides, {}, "a missing overrides section must default to empty");
        sameJson(partial.disabled, [], "a missing disabled section must default to empty");
    }

    function test_render_overlay_is_stable_indented_json() {
        compare(KeybindStore.renderOverlay(KeybindStore.newOverlay()),
            '{\n  "overrides": {},\n  "adds": [],\n  "disabled": []\n}\n',
            "the on-disk JSON shape is part of the generator contract");
        verify(KeybindStore.renderOverlay(KeybindStore.newOverlay()).endsWith("\n"),
            "the overlay file must end with a newline");
    }

    // --- create / update / remove, then verify the emitted JSON ---------------

    function test_create_add_renders_exact_overlay_json_and_round_trips() {
        let overlay = KeybindStore.newOverlay();
        overlay.disabled = ["cat-b"];
        const created = createAdd(overlay, "add-one",
            addEntry("", "Test bind", "Utilities", "true", "SUPER + F12"));
        overlay = created.overlay;

        const expected = '{\n'
            + '  "overrides": {},\n'
            + '  "adds": [\n'
            + '    {\n'
            + '      "id": "add-one",\n'
            + '      "category": "Utilities",\n'
            + '      "combo": "SUPER + F12",\n'
            + '      "description": "Test bind",\n'
            + '      "dispatch": {\n'
            + '        "kind": "command",\n'
            + '        "id": "add-one",\n'
            + '        "command": "true"\n'
            + '      },\n'
            + '      "options": {},\n'
            + '      "source": "custom",\n'
            + '      "code": "hl.bind(\\"SUPER + F12\\", hl.dsp.exec_cmd(\\"true\\"), { description = \\"Test bind\\" })"\n'
            + '    }\n'
            + '  ],\n'
            + '  "disabled": [\n'
            + '    "cat-b"\n'
            + '  ]\n'
            + '}\n';
        const text = KeybindStore.renderOverlay(overlay);
        compare(text, expected, "the generated overlay JSON changed:\n" + text);

        // The file the generator reads must parse back to the very same data.
        const reparsed = KeybindStore.parseOverlay(text);
        sameJson(reparsed, overlay, "render -> parse must be lossless");
        compare(reparsed.adds[0].dispatch.command, "true");
        compare(reparsed.disabled[0], "cat-b");
    }

    function test_add_to_entry_is_the_editable_view_of_an_add() {
        const created = createAdd(KeybindStore.newOverlay(), "add-two",
            addEntry("", "Renamed", "Media", "playerctl next", "SUPER + N"));
        const entry = KeybindStore.addToEntry(created.add);
        sameJson(entry, {
            id: "add-two",
            name: "Renamed",
            category: "Media",
            combo: "SUPER + N",
            command: "playerctl next",
            code: created.add.code,
            raw: false
        });
        // The form's name/command are stored as description/dispatch.command.
        compare(created.add.description, "Renamed");
        compare(created.add.dispatch.kind, "command");
    }

    function test_make_add_escapes_lua_code_and_keeps_the_entry_id() {
        const add = KeybindStore.makeAdd(
            addEntry("ignored", 'Say "hi"', "", 'echo "x"', "SUPER + Q"), "fixed-id");
        compare(add.id, "fixed-id", "the id passed in wins over the entry id");
        compare(add.dispatch.id, "fixed-id");
        compare(add.code,
            'hl.bind("SUPER + Q", hl.dsp.exec_cmd("echo \\"x\\""), { description = "Say \\"hi\\"" })',
            "quotes in the name and command must be escaped in the Lua fallback");
        const roundTrip = KeybindStore.parseOverlay(KeybindStore.renderOverlay(
            KeybindStore.withAdds(KeybindStore.newOverlay(), [add])));
        compare(roundTrip.adds[0].code, add.code);
    }

    function test_update_changes_only_the_target_add() {
        const first = createAdd(KeybindStore.newOverlay(), "first",
            addEntry("", "First", "Apps", "true", "SUPER + F12"));
        const second = createAdd(first.overlay, "second",
            addEntry("", "Second", "Apps", "false", "SUPER + F11"));
        compare(second.overlay.adds.length, 2);

        // Mirrors ManagedKeybinds.update(): rebuild the add for one id,
        // keep every other add byte-for-byte.
        const adds = second.overlay.adds.slice();
        const current = KeybindStore.addToEntry(adds[0]);
        const next = Object.assign({}, current, { name: "Renamed", combo: "SUPER + F10" });
        adds[0] = KeybindStore.makeAdd(next, "first");
        const updated = KeybindStore.withAdds(second.overlay, adds);

        const reparsed = KeybindStore.parseOverlay(KeybindStore.renderOverlay(updated));
        compare(reparsed.adds.length, 2);
        compare(reparsed.adds[0].description, "Renamed");
        compare(reparsed.adds[0].combo, "SUPER + F10");
        compare(reparsed.adds[0].dispatch.command, "true", "an untouched field must survive an update");
        compare(reparsed.adds[1].description, "Second", "the neighbouring add must not change");
        verify(reparsed.adds[0].id === "first" && reparsed.adds[1].id === "second");
    }

    function test_remove_drops_only_the_target_add() {
        const first = createAdd(KeybindStore.newOverlay(), "first",
            addEntry("", "First", "", "true", "SUPER + F12"));
        const second = createAdd(first.overlay, "second",
            addEntry("", "Second", "", "false", "SUPER + F11"));
        const removed = KeybindStore.withAdds(second.overlay,
            second.overlay.adds.filter(item => item.id !== "first"));

        const reparsed = KeybindStore.parseOverlay(KeybindStore.renderOverlay(removed));
        compare(reparsed.adds.length, 1);
        compare(reparsed.adds[0].id, "second");
        compare(reparsed.adds[0].description, "Second");
    }

    function test_with_adds_and_with_overrides_preserve_other_sections() {
        const base = KeybindStore.newOverlay();
        base.disabled = ["cat-b"];
        const first = createAdd(base, "first", addEntry("", "One", "", "true", "F9"));
        const withOverrides = KeybindStore.withOverrides(first.overlay,
            { "cat-a": KeybindStore.comboOverride("SUPER + Z") });

        sameJson(withOverrides.adds, first.overlay.adds, "withOverrides must keep adds");
        sameJson(withOverrides.disabled, ["cat-b"], "withOverrides must keep disabled");
        compare(withOverrides.overrides["cat-a"].combo, "SUPER + Z");

        const withAdds = KeybindStore.withAdds(withOverrides, withOverrides.adds.slice(0, 1));
        sameJson(withAdds.overrides, withOverrides.overrides, "withAdds must keep overrides");
        sameJson(withAdds.disabled, ["cat-b"], "withAdds must keep disabled");
        compare(withAdds.adds.length, 1);

        // Neither helper mutates the overlay it was given.
        compare(base.adds.length, 0, "the input overlay was mutated");
        sameJson(base.overrides, {}, "the input overlay was mutated");
    }

    function test_combo_override_is_a_narrow_patch() {
        sameJson(KeybindStore.comboOverride("SUPER + Z"), { combo: "SUPER + Z" });
        sameJson(KeybindStore.comboOverride(undefined), { combo: "" });
    }

    function test_validate_rejects_an_invalid_entry_without_building_an_add() {
        compare(KeybindStore.validate(addEntry("", "Name", "", "true", "F9")), "");
        compare(KeybindStore.validate(addEntry("", "", "", "true", "F9")), "empty-name");
        compare(KeybindStore.validate(addEntry("", 'Say "hi"', "", "true", "F9")), "quote-name");
        compare(KeybindStore.validate(addEntry("", "Name", "", "", "F9")), "empty-command");
        compare(KeybindStore.validate(addEntry("", "Name", "", "true", "")), "empty-combo");
    }

    // --- effectiveBinds: the merge the generator and the panel both read -------

    function test_effective_binds_applies_disabled_overrides_and_adds() {
        const catalog = sampleCatalog();
        const overlay = KeybindStore.newOverlay();
        overlay.overrides = {
            "cat-a": {
                combo: "SUPER + Z",
                description: "Alpha renamed",
                category: "Custom",
                dispatch: { kind: "command", id: "cat-a", command: "rebound" },
                options: { transparent: true }
            },
            "cat-c": { enabled: false }
        };
        overlay.disabled = ["cat-b"];
        overlay.adds = [
            KeybindStore.makeAdd(addEntry("", "My bind", "Utilities", "true", "SUPER + F12"), "usr-1"),
            // A hand-written add with only the essential fields must get the
            // defaults effectiveBinds supplies.
            { id: "usr-2", combo: "F8", name: "Bare" }
        ];

        const binds = KeybindStore.effectiveBinds(catalog, overlay);
        // cat-b is disabled by the disabled list, cat-c by enabled:false.
        compare(binds.length, 3, "expected cat-a plus the two adds");

        const alpha = binds[0];
        compare(alpha.id, "cat-a");
        compare(alpha.combo, "SUPER + Z", "the override combo must win");
        compare(alpha.description, "Alpha renamed");
        compare(alpha.category, "Custom");
        compare(alpha.dispatch.command, "rebound");
        sameJson(alpha.options, { transparent: true });
        compare(alpha.originalCombo, "SUPER + A", "the frozen combo must be recorded for the old config path");
        compare(alpha.code, "frozen code for cat-a", "code stays with the frozen catalog");
        compare(alpha.source, "main", "source stays with the frozen catalog");
        compare(alpha.line, 42, "line stays with the frozen catalog");

        const userAdd = binds[1];
        compare(userAdd.id, "usr-1");
        compare(userAdd.description, "My bind");
        compare(userAdd.dispatch.command, "true");
        compare(userAdd.source, "custom");
        sameJson(userAdd.options, {});

        const bare = binds[2];
        compare(bare.id, "usr-2");
        compare(bare.combo, "F8");
        compare(bare.description, "Bare", "a bare add's name becomes its description");
        compare(bare.category, "", "a bare add's category defaults to empty");
        compare(bare.source, "custom");
        sameJson(bare.options, {});
        sameJson(bare.dispatch, { kind: "command", id: "usr-2", command: "" },
            "a bare add gets a command dispatch fallback");
    }

    function test_effective_binds_ignores_overrides_for_disabled_ids() {
        const overlay = KeybindStore.newOverlay();
        overlay.disabled = ["cat-a"];
        overlay.overrides = { "cat-a": { combo: "SUPER + Z" } };
        const binds = KeybindStore.effectiveBinds(sampleCatalog(), overlay);
        compare(binds.length, 2);
        compare(binds[0].id, "cat-b");
        compare(binds[1].id, "cat-c");
    }

    function test_effective_binds_of_an_empty_overlay_equals_the_catalog() {
        const catalog = sampleCatalog();
        const binds = KeybindStore.effectiveBinds(catalog, KeybindStore.newOverlay());
        compare(binds.length, 3);
        compare(binds[0].id, "cat-a");
        compare(binds[0].combo, "SUPER + A");
        verify(binds[0].originalCombo === undefined, "an unoverridden bind has no originalCombo");
        sameJson(binds[0].options, { locked: true });
    }

    function test_effective_binds_does_not_mutate_its_inputs() {
        const catalog = sampleCatalog();
        const overlay = KeybindStore.newOverlay();
        overlay.overrides = { "cat-a": KeybindStore.comboOverride("SUPER + Z") };
        overlay.adds = [KeybindStore.makeAdd(addEntry("", "Mine", "", "true", "F9"), "usr-1")];
        const catalogBefore = JSON.stringify(catalog);
        const overlayBefore = JSON.stringify(overlay);

        KeybindStore.effectiveBinds(catalog, overlay);

        compare(JSON.stringify(catalog), catalogBefore, "the frozen catalog was mutated");
        compare(JSON.stringify(overlay), overlayBefore, "the overlay was mutated");
    }

    // The full path, end to end: edits -> rendered overlay -> parsed file ->
    // merged binds. This is the sequence a settings write followed by the
    // generator's reload produces.
    function test_overlay_round_trip_feeds_effective_binds() {
        const catalog = sampleCatalog();
        let overlay = KeybindStore.newOverlay();
        overlay = KeybindStore.withOverrides(overlay,
            { "cat-a": KeybindStore.comboOverride("SUPER + Z") });
        overlay = createAdd(overlay, "usr-1",
            addEntry("", "My bind", "Utilities", "true", "SUPER + F12")).overlay;

        const onDisk = KeybindStore.parseOverlay(KeybindStore.renderOverlay(overlay));
        const binds = KeybindStore.effectiveBinds(catalog, onDisk);

        compare(binds.length, 4);
        compare(binds[0].combo, "SUPER + Z");
        compare(binds[0].originalCombo, "SUPER + A");
        compare(binds[1].id, "cat-b");
        compare(binds[2].id, "cat-c");
        compare(binds[3].id, "usr-1");
        compare(binds[3].combo, "SUPER + F12");
        compare(binds[3].source, "custom");
    }
}
