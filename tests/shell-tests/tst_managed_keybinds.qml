import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import "modules/common/functions/KeybindStore.js" as KeybindStore

/**
 * HOSTED (Quickshell) test for the overlay-backed keybind manager.
 *
 * ManagedKeybinds no longer round-trips the removed Lua managed-block
 * markers. It now owns a single JSON file,
 * ~/.config/hypr/custom/keybind-overlay.json, exposes its adds through
 * editableEntries, and runs the catalog generator after every save.
 *
 * This test drives the real singleton against an OVERRIDDEN TEMP PATH. The
 * injectable keybindsPath property is repointed at a file under /tmp before
 * any edit, so the user's real overlay is never read for editing or written.
 * Each write still goes through the component's normal save chain
 * (FileView.setText -> generator hook), so this belongs in the headless
 * shell harness (tests/run-shell-tests.sh), never in a live Hyprland session.
 *
 * LIMITATION: qmltestrunner cannot resolve "import Quickshell"/"qs.services",
 * so this file cannot be executed by qmltestrunner directly; it is compiled
 * by tests/qml-compile-check.sh and executed inside tests/shell-tests/shell.qml.
 * The pure-JS half of the overlay (renderOverlay/parseOverlay/effectiveBinds)
 * is covered by modules/common/functions/tst_managed_keybinds.qml and is not
 * duplicated here.
 */
TestCase {
    id: testCase
    name: "ManagedKeybindsOverlay"
    when: true

    readonly property string tempDir: "/tmp/opencode/tst_managed_keybinds_overlay"
    readonly property string tempPath: tempDir + "/keybind-overlay.json"

    property string originalPath: ""
    property bool seedDone: false
    property bool readerLoaded: false
    property var reader: null

    // A form entry in the shape ManagedKeybinds.create() accepts.
    function formEntry(name, category, command, combo) {
        return { name: name, category: category, command: command, combo: combo };
    }

    // The overlay on disk is plain JSON: seed it with an explicit skeleton so
    // every test starts from a known state. No Lua markers are involved.
    function seedOverlay(entries) {
        const overlay = KeybindStore.newOverlay();
        overlay.adds = entries ?? [];
        seedOverlayText(KeybindStore.renderOverlay(overlay));
    }

    function seedOverlayText(text) {
        testCase.seedDone = false;
        seedProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\"",
            "seed", testCase.tempDir, text, testCase.tempPath];
        seedProc.running = true;
        tryCompare(testCase, "seedDone", true, 5000, "the temp overlay was never seeded");
    }

    Process {
        id: seedProc
        onExited: testCase.seedDone = true
    }

    // Repoint the singleton at the temp overlay and force a real re-read.
    // Hopping away and back is deliberate: FileView's change watch is not
    // reliable for a file rewritten in the same tick as the seed.
    function bindTempOverlay() {
        tryCompare(ManagedKeybinds, "pendingWrite", false, 5000);
        let generation = ManagedKeybinds.loadGeneration;
        if (ManagedKeybinds.keybindsPath !== testCase.tempPath) {
            ManagedKeybinds.keybindsPath = testCase.tempPath;
        } else {
            ManagedKeybinds.keybindsPath = testCase.originalPath;
            tryVerify(() => ManagedKeybinds.loadGeneration > generation, 5000,
                "the hop back to the default path never loaded");
            generation = ManagedKeybinds.loadGeneration;
            ManagedKeybinds.keybindsPath = testCase.tempPath;
        }
        tryVerify(() => ManagedKeybinds.loadGeneration > generation, 5000,
            "the switch to the temp overlay never loaded");
        verify(ManagedKeybinds.loaded, "the temp overlay was never reported as loaded");
    }

    function reseed(entries) {
        seedOverlay(entries);
        bindTempOverlay();
    }

    // A fresh reader for every read, created with its path at construction
    // time, so no assertion can pass or fail on a stale watch.
    function readTempOverlay() {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        testCase.readerLoaded = false;
        testCase.reader = readerComponent.createObject(testCase, { "path": testCase.tempPath });
        tryCompare(testCase, "readerLoaded", true, 5000, "the temp overlay reader never loaded");
        return testCase.reader.text();
    }

    Component {
        id: readerComponent
        FileView {
            preload: true
            onLoaded: testCase.readerLoaded = true
        }
    }

    // A save is only done once the temp file on disk shows the new bytes;
    // polling the file avoids assuming the generator hook is synchronous.
    function waitForFileToContain(fragment, message) {
        tryVerify(() => readTempOverlay().indexOf(fragment) !== -1, 5000, message);
    }

    function waitForFileToLose(fragment, message) {
        tryVerify(() => readTempOverlay().indexOf(fragment) === -1, 5000, message);
    }

    function addInFile(id) {
        const adds = KeybindStore.parseOverlay(readTempOverlay()).adds;
        return adds.find(add => add.id === id);
    }

    function createAndWait(name, command, combo) {
        const created = ManagedKeybinds.create(formEntry(name, "Utilities", command, combo));
        verify(created.ok, "create failed: " + created.error);
        waitForFileToContain('"id": "' + created.id + '"',
            "the new add never reached the temp overlay: " + readTempOverlay());
        return created;
    }

    function init() {
        if (testCase.originalPath === "")
            testCase.originalPath = ManagedKeybinds.keybindsPath;
        seedOverlay([]);
        bindTempOverlay();
        compare(ManagedKeybinds.entries.length, 0, "a fresh temp overlay must have no adds");
    }

    function cleanupTestCase() {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        // Point the singleton back at its default path before deleting /tmp.
        if (testCase.originalPath !== "")
            ManagedKeybinds.keybindsPath = testCase.originalPath;
        Quickshell.execDetached(["rm", "-rf", testCase.tempDir]);
    }

    // --- public API shape and overlay path -----------------------------------

    function test_overlay_path_points_at_the_overlay_json() {
        const basename = testCase.originalPath.split("/").pop();
        compare(basename, "keybind-overlay.json",
            "the default path must name the JSON overlay, not a Lua file");
        verify(testCase.originalPath.indexOf("/hypr/custom/") !== -1,
            "the overlay must live under hypr/custom: " + testCase.originalPath);
        compare(ManagedKeybinds.keybindsPath, testCase.tempPath,
            "the test must have overridden the overlay path");
        verify(ManagedKeybinds.keybindsPath !== testCase.originalPath,
            "the real overlay must never be the write target");
    }

    function test_editable_entries_is_exposed_and_maps_overlay_adds() {
        verify(ManagedKeybinds.editableEntries !== undefined, "editableEntries is not exposed");
        verify(Array.isArray(ManagedKeybinds.editableEntries), "editableEntries is not an array");
        compare(JSON.stringify(ManagedKeybinds.editableEntries),
            JSON.stringify(ManagedKeybinds.entries),
            "editableEntries must be the form's view of every overlay add");

        const add = KeybindStore.makeAdd(
            formEntry("Seed bind", "Utilities", "true", "SUPER + F12"), "seed-1");
        reseed([add]);

        compare(ManagedKeybinds.editableEntries.length, 1);
        const entry = ManagedKeybinds.editableEntries[0];
        compare(entry.id, "seed-1");
        compare(entry.name, "Seed bind");
        compare(entry.command, "true");
        compare(entry.combo, "SUPER + F12");
        compare(entry.raw, false, "JSON overlay adds are always editable; there is no raw residue");
    }

    // --- create / update / remove, verified on the OVERRIDDEN temp path ------

    function test_create_writes_the_add_to_the_temp_overlay() {
        const created = createAndWait("Test bind", "true", "SUPER + F12");

        const add = addInFile(created.id);
        verify(add !== undefined, "the created add is missing from the temp overlay");
        compare(add.description, "Test bind");
        compare(add.category, "Utilities");
        compare(add.combo, "SUPER + F12");
        compare(add.dispatch.command, "true");
        compare(add.source, "custom");

        const entry = ManagedKeybinds.editableEntries.find(e => e.id === created.id);
        verify(entry !== undefined, "the new add is not offered back as an editable entry");
        compare(entry.name, "Test bind");
        compare(entry.combo, "SUPER + F12");
    }

    function test_update_rewrites_only_the_target_add_in_the_temp_overlay() {
        const first = createAndWait("First", "true", "SUPER + F12");
        const second = createAndWait("Second", "false", "SUPER + F11");

        const updated = ManagedKeybinds.update(first.id, { name: "Renamed", combo: "SUPER + F10" });
        verify(updated.ok, "update failed: " + updated.error);
        waitForFileToContain('"description": "Renamed"', "the rename never reached the temp overlay");

        const overlay = KeybindStore.parseOverlay(readTempOverlay());
        compare(overlay.adds.length, 2, "an update must not add or drop adds");
        const changed = overlay.adds.find(add => add.id === first.id);
        const neighbour = overlay.adds.find(add => add.id === second.id);
        verify(changed !== undefined && neighbour !== undefined, "an add was lost on update");
        compare(changed.description, "Renamed");
        compare(changed.combo, "SUPER + F10");
        compare(changed.dispatch.command, "true", "an untouched field must survive an update");
        compare(neighbour.description, "Second", "the neighbouring add must not change");
        compare(neighbour.combo, "SUPER + F11");
    }

    function test_remove_drops_only_the_target_add_from_the_temp_overlay() {
        const first = createAndWait("Doomed", "true", "SUPER + F12");
        const second = createAndWait("Keeper", "false", "SUPER + F11");

        const removed = ManagedKeybinds.remove(first.id);
        verify(removed.ok, "remove failed: " + removed.error);
        waitForFileToLose('"id": "' + first.id + '"', "the removed id is still in the temp overlay");

        const overlay = KeybindStore.parseOverlay(readTempOverlay());
        compare(overlay.adds.length, 1);
        compare(overlay.adds[0].id, second.id);
        compare(overlay.adds[0].description, "Keeper");
        verify(ManagedKeybinds.editableEntries.find(e => e.id === first.id) === undefined,
            "the removed add is still offered to the form");
    }

    function test_set_and_clear_override_write_to_the_temp_overlay() {
        const set = ManagedKeybinds.setOverride("frozen-bind", "SUPER + Z");
        verify(set.ok, "setOverride failed: " + set.error);
        waitForFileToContain('"frozen-bind"', "the override never reached the temp overlay");
        let overlay = KeybindStore.parseOverlay(readTempOverlay());
        compare(overlay.overrides["frozen-bind"].combo, "SUPER + Z");
        compare(overlay.adds.length, 0, "an override must not create an add");

        const cleared = ManagedKeybinds.clearOverride("frozen-bind");
        verify(cleared.ok, "clearOverride failed: " + cleared.error);
        waitForFileToLose('"frozen-bind"', "the override is still in the temp overlay");
        overlay = KeybindStore.parseOverlay(readTempOverlay());
        compare(Object.keys(overlay.overrides).length, 0);
    }

    // --- validation and lookup, no file writes -------------------------------

    function test_validate_reports_the_store_codes() {
        compare(ManagedKeybinds.validate(formEntry("Ok", "", "true", "SUPER + K")), "");
        compare(ManagedKeybinds.validate(formEntry("", "", "true", "SUPER + K")), "empty-name");
        compare(ManagedKeybinds.validate(formEntry("A", "", "", "SUPER + K")), "empty-command");
        compare(ManagedKeybinds.validate(formEntry("A", "", "true", "")), "empty-combo");
        compare(ManagedKeybinds.validate(formEntry('Say "hi"', "", "true", "SUPER + K")), "quote-name");
    }

    function test_update_and_remove_report_unknown_ids() {
        const entriesBefore = ManagedKeybinds.entries.length;

        const updated = ManagedKeybinds.update("does-not-exist", formEntry("x", "", "y", "z"));
        verify(!updated.ok);
        compare(updated.error, "not-found");

        const removed = ManagedKeybinds.remove("does-not-exist");
        verify(!removed.ok);
        compare(removed.error, "not-found");

        compare(ManagedKeybinds.entries.length, entriesBefore,
            "an unknown id must not change the editable entries");
        verify(!readTempOverlay().includes('does-not-exist'),
            "an unknown id must not write to the temp overlay");
    }

    // Overlay-backed counterpart of the old line-metadata lookup: an add is
    // identified by the overlay path plus its id, never by a Lua line number.
    function test_entry_for_source_matches_the_overlay_path() {
        const created = createAndWait("Source bind", "true", "SUPER + F7");

        const inside = { sourcePath: testCase.tempPath, id: created.id };
        const found = ManagedKeybinds.entryForSource(inside);
        verify(found !== null, "entryForSource rejected an add from the overlay");
        compare(found.id, created.id);

        const wrongFile = { sourcePath: "/some/other/keybind-overlay.json", id: created.id };
        verify(ManagedKeybinds.entryForSource(wrongFile) === null,
            "entryForSource must reject a bind from a different file");

        const missingId = { sourcePath: testCase.tempPath, id: "does-not-exist" };
        verify(ManagedKeybinds.entryForSource(missingId) === null,
            "entryForSource must reject an id that is not an overlay add");
    }

    // --- default binds: disable durability and combo overrides --------------

    // The regression the marker-based delete caused: a default bind was
    // commented out in generated Lua, then the next overlay save regenerated
    // the file and silently brought it back. Here the disable is an overlay id,
    // so every later save keeps it.
    function test_disable_default_bind_then_overlay_save_stays_disabled() {
        reseed([]);
        const disabled = ManagedKeybinds.disable("screen");
        verify(disabled.ok, "disable failed: " + disabled.error);
        waitForFileToContain('"screen"', "the disabled id never reached the temp overlay");
        verify(ManagedKeybinds.isDisabled("screen"));

        let overlay = KeybindStore.parseOverlay(readTempOverlay());
        compare(overlay.disabled.indexOf("screen") !== -1, true);

        // An unrelated create rewrites the whole overlay file.
        const created = createAndWait("After delete", "true", "SUPER + F12");
        overlay = KeybindStore.parseOverlay(readTempOverlay());
        compare(overlay.disabled.indexOf("screen") !== -1, true,
            "the next overlay save undid the delete:\n" + readTempOverlay());

        // The list the settings page reads still omits the deleted bind.
        const catalog = { binds: [{
            id: "screen", combo: "SUPER + Minus", description: "Screen",
            category: "Screen", source: "main",
            dispatch: { kind: "raw", code: "hl.bind(\"SUPER + Minus\", function() end)" }
        }] };
        const binds = KeybindStore.effectiveBinds(catalog, overlay);
        compare(binds.length, 1, "the deleted default bind reappeared in effectiveBinds");
        compare(binds[0].id, created.id);

        const restored = ManagedKeybinds.enable("screen");
        verify(restored.ok, "enable failed: " + restored.error);
        waitForFileToLose('"screen"', "the restored id is still in the temp overlay");
        verify(!ManagedKeybinds.isDisabled("screen"));
    }

    function test_update_of_a_default_bind_writes_an_overlay_override() {
        reseed([]);
        const updated = ManagedKeybinds.update("bind", { combo: "SUPER + GRAVE" });
        verify(updated.ok, "update of a catalog id failed: " + updated.error);
        waitForFileToContain('"bind"', "the override never reached the temp overlay");

        const overlay = KeybindStore.parseOverlay(readTempOverlay());
        compare(overlay.overrides["bind"].combo, "SUPER + GRAVE");
        compare(overlay.adds.length, 0, "an override must not create an add");
        verify(ManagedKeybinds.isOverridden("bind"));

        const cleared = ManagedKeybinds.clearOverride("bind");
        verify(cleared.ok, "clearOverride failed: " + cleared.error);
        waitForFileToLose('"bind"', "the override is still in the temp overlay");
        verify(!ManagedKeybinds.isOverridden("bind"));
    }

    function test_raw_default_bind_refuses_a_combo_override() {
        tryVerify(() => ManagedKeybinds.catalogLoaded, 5000,
            "the catalog never loaded, so raw binds cannot be recognised");
        reseed([]);
        const viaSetter = ManagedKeybinds.setOverride("screen", "SUPER + Z");
        verify(!viaSetter.ok, "a raw bind's combo must not be overridable");
        compare(viaSetter.error, "raw-combo");

        const viaUpdate = ManagedKeybinds.update("screen", { combo: "SUPER + Z" });
        verify(!viaUpdate.ok, "update must refuse a raw bind too");
        compare(viaUpdate.error, "raw-combo");
        verify(readTempOverlay().indexOf("screen") === -1,
            "nothing may be written for a refused raw override");
    }
}
