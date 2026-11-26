import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import "modules/common/functions/KeybindStore.js" as KeybindStore

/**
 * The write path of the recoverable "delete keybind" feature.
 *
 * A delete is no longer a comment marker spliced into generated Lua: it is a
 * catalog id in the overlay JSON, written through ManagedKeybinds, so the next
 * generator run cannot resurrect the bind. The service keeps read-only Lua
 * snapshots only to label a row with its source file.
 *
 * The overlay path and the two Lua snapshot paths are all overridden to temp
 * files here, so the user's real overlay and generated Lua are never edited by
 * a test. Every test reseeds the overlay and checks that both Lua snapshots
 * stay byte-for-byte unchanged after a disable and after a restore.
 */
TestCase {
    id: testCase
    name: "DisabledKeybinds"
    when: true

    readonly property string tempDir: "/tmp/end4pc-shell-tests/tst_disabled_keybinds"
    readonly property string mainPath: tempDir + "/hyprland-keybinds.lua"
    readonly property string customPath: tempDir + "/custom-keybinds.lua"
    readonly property string overlayPath: tempDir + "/keybind-overlay.json"

    property string originalMainPath: ""
    property string originalCustomPath: ""
    property string originalOverlayPath: ""
    property bool seedDone: false
    property bool readerLoaded: false
    property var reader: null

    function mainText() {
        return "-- main head\n"
            + "hl.bind(\"SUPER + T\", hl.dsp.exec_cmd(\"kitty\"), {description = \"Terminal\"})\n"
            + "hl.bind(\"SUPER + B\", hl.dsp.exec_cmd(\"firefox\"), {description = \"Browser\"})\n"
            + "-- main tail\n";
    }

    function customText() {
        return "-- custom head\n"
            + "hl.bind(\"CTRL + C\", hl.dsp.exec_cmd(\"code\"), {description = \"Editor\"})\n"
            + "-- custom tail\n";
    }

    // A bind as the settings pane hands it to disableBinds: the catalog id is
    // the only part that decides what is written. Action/combo are used solely
    // to clear a stale bind override in the same save.
    function bind(catalogId, action, mods, key) {
        const result = { id: catalogId };
        if (action) result.action = action;
        if (mods) result.mods = mods;
        if (key) result.key = key;
        return result;
    }

    function seedFile(path, text) {
        testCase.seedDone = false;
        seedProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\"",
            "seed", testCase.tempDir, text, path];
        seedProc.running = true;
        tryCompare(testCase, "seedDone", true, 5000, "the seed was never written: " + path);
    }

    function seedBoth(main, custom) {
        testCase.seedDone = false;
        seedProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\" && printf '%s' \"$4\" > \"$5\"",
            "seed", testCase.tempDir, main, testCase.mainPath, custom, testCase.customPath];
        seedProc.running = true;
        tryCompare(testCase, "seedDone", true, 5000, "the seed was never written");
    }

    function seedOverlay(disabled) {
        const overlay = KeybindStore.newOverlay();
        overlay.disabled = disabled ?? [];
        seedFile(testCase.overlayPath, KeybindStore.renderOverlay(overlay));
    }

    Process {
        id: seedProc
        onExited: testCase.seedDone = true
    }

    Component {
        id: readerComponent
        FileView {
            preload: true
            onLoaded: testCase.readerLoaded = true
        }
    }

    // A fresh reader per read, so no assertion can pass on a stale watch.
    function fileText(path) {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        testCase.readerLoaded = false;
        testCase.reader = readerComponent.createObject(testCase, { "path": path });
        tryCompare(testCase, "readerLoaded", true, 5000, "the reader never loaded " + path);
        return testCase.reader.text();
    }

    function overlay() {
        return KeybindStore.parseOverlay(fileText(testCase.overlayPath));
    }

    function entryFor(id) {
        return DisabledKeybinds.disabled.find(entry => entry.id === id);
    }

    function waitForSave(generation) {
        tryCompare(ManagedKeybinds, "pendingWrite", false, 5000,
            "the overlay save never finished");
        tryVerify(() => DisabledKeybinds.loadGeneration > generation, 5000,
            "the overlay change never landed (loadGeneration stayed at " + generation + ")");
        // DisabledKeybinds bumps loadGeneration synchronously, while the
        // FileView write is still async. Wait until the file really shows the
        // in-memory overlay before asserting on it.
        const expected = KeybindStore.renderOverlay(ManagedKeybinds.overlay);
        tryVerify(() => KeybindStore.renderOverlay(testCase.overlay()) === expected, 5000,
            "the overlay file never reflected the in-memory change");
        // A stale FileView watch can briefly rebuild the list from the old
        // file; wait for the service to settle on the in-memory ids too.
        const expectedDisabled = (ManagedKeybinds.overlay?.disabled ?? []).length;
        tryVerify(() => DisabledKeybinds.disabled.length === expectedDisabled, 5000,
            "the Deleted section never settled on the saved ids");
    }

    // Repoint the manager at the temp overlay and force a real re-read. The
    // hop away and back is deliberate: a file rewritten in the same tick as
    // the seed is not always picked up by FileView's watch.
    function bindTempOverlay() {
        tryCompare(ManagedKeybinds, "pendingWrite", false, 5000);
        let generation = ManagedKeybinds.loadGeneration;
        if (ManagedKeybinds.keybindsPath !== testCase.overlayPath) {
            ManagedKeybinds.keybindsPath = testCase.overlayPath;
        } else {
            ManagedKeybinds.keybindsPath = testCase.originalOverlayPath;
            tryVerify(() => ManagedKeybinds.loadGeneration > generation, 5000,
                "the hop away from the temp overlay never loaded");
            generation = ManagedKeybinds.loadGeneration;
            ManagedKeybinds.keybindsPath = testCase.overlayPath;
        }
        tryVerify(() => ManagedKeybinds.loadGeneration > generation, 5000,
            "the switch to the temp overlay never loaded");
        verify(ManagedKeybinds.loaded, "the temp overlay was never reported as loaded");
    }

    function init() {
        // The previous test's FileView reloads are async. Let them finish
        // before resetting the label maps, or a late rebuild can repopulate
        // the list from a stale overlay with the new (empty) maps.
        tryCompare(ManagedKeybinds, "pendingWrite", false, 5000);
        wait(150);

        if (testCase.originalMainPath === "")
            testCase.originalMainPath = DisabledKeybinds.defaultKeybindConfigPath;
        if (testCase.originalCustomPath === "")
            testCase.originalCustomPath = DisabledKeybinds.userKeybindConfigPath;
        if (testCase.originalOverlayPath === "")
            testCase.originalOverlayPath = ManagedKeybinds.keybindsPath;

        // Look away from the temp overlay before reseeding it. Otherwise the
        // FileView watch sees the seed write and can reload an empty overlay
        // after the previous test's last save has already landed.
        if (testCase.originalOverlayPath !== ""
            && ManagedKeybinds.keybindsPath === testCase.overlayPath) {
            const awayGeneration = ManagedKeybinds.loadGeneration;
            ManagedKeybinds.keybindsPath = testCase.originalOverlayPath;
            tryVerify(() => ManagedKeybinds.loadGeneration > awayGeneration, 5000,
                "the init hop away from the temp overlay never loaded");
        }

        // The label/file maps are per-session bookkeeping; a fresh test must
        // not inherit the grouping established by the previous one.
        DisabledKeybinds.catalogIdsByEntry = {};
        DisabledKeybinds.entryByCatalogId = {};
        DisabledKeybinds.labelById = {};

        seedBoth(testCase.mainText(), testCase.customText());
        seedOverlay([]);

        let generation = DisabledKeybinds.loadGeneration;
        if (DisabledKeybinds.defaultKeybindConfigPath === testCase.originalMainPath) {
            DisabledKeybinds.defaultKeybindConfigPath = testCase.mainPath;
            DisabledKeybinds.userKeybindConfigPath = testCase.customPath;
        } else {
            DisabledKeybinds.defaultKeybindConfigPath = testCase.originalMainPath;
            DisabledKeybinds.userKeybindConfigPath = testCase.originalCustomPath;
            tryVerify(() => DisabledKeybinds.loadGeneration > generation, 5000,
                "the hop away never loaded");
            const away = DisabledKeybinds.loadGeneration;
            DisabledKeybinds.defaultKeybindConfigPath = testCase.mainPath;
            DisabledKeybinds.userKeybindConfigPath = testCase.customPath;
            tryVerify(() => DisabledKeybinds.loadGeneration > away, 5000,
                "the hop back never loaded");
        }
        bindTempOverlay();
        tryVerify(() => DisabledKeybinds.ready && ManagedKeybinds.loaded, 5000,
            "the service never loaded both seeded snapshots and the temp overlay");
    }

    function cleanup() {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        const action = "zzDisabledKeybindsTestAction";
        if (HyprlandBindOverrides.isOverridden(action))
            HyprlandBindOverrides.clearOverride(action);
        const plainOverrideId = "bind_" + "SUPER + T".replace(/[^A-Za-z0-9_]/g, "_");
        if (HyprlandBindOverrides.isOverridden(plainOverrideId))
            HyprlandBindOverrides.clearOverride(plainOverrideId);
    }

    function cleanupTestCase() {
        if (testCase.originalMainPath !== "") {
            DisabledKeybinds.defaultKeybindConfigPath = testCase.originalMainPath;
            DisabledKeybinds.userKeybindConfigPath = testCase.originalCustomPath;
        }
        if (testCase.originalOverlayPath !== "")
            ManagedKeybinds.keybindsPath = testCase.originalOverlayPath;
        Quickshell.execDetached(["rm", "-rf", testCase.tempDir]);
    }

    function test_disable_one_bind_writes_the_catalog_id_and_updates_state() {
        const generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "main:Snip", "Screen snip",
            [testCase.bind("utilities", "actionSnip", ["SUPER", "SHIFT"], "S")]);
        verify(result.ok, "disableBinds failed: " + result.error);
        waitForSave(generation);

        const disabled = testCase.overlay().disabled;
        compare(disabled.length, 1, "exactly one catalog id must be disabled");
        compare(disabled[0], "utilities");

        const entry = testCase.entryFor("main:Snip");
        verify(entry !== undefined, "disabled did not get the new entry");
        compare(entry.label, "Screen snip");
        compare(entry.file, "main");
        verify(DisabledKeybinds.isDisabled("main:Snip"));
        verify(!DisabledKeybinds.isDisabled("main:Missing"));
        compare(testCase.fileText(testCase.mainPath), testCase.mainText(),
            "the generated Lua must never be edited by a delete");
    }

    function test_restore_removes_the_id_and_leaves_the_lua_unchanged() {
        const original = testCase.mainText();
        let generation = DisabledKeybinds.loadGeneration;
        const removed = DisabledKeybinds.disableBinds(
            "main:Snip", "Screen snip",
            [testCase.bind("utilities", "actionSnip", ["SUPER", "SHIFT"], "S")]);
        verify(removed.ok, "disableBinds failed: " + removed.error);
        waitForSave(generation);

        generation = DisabledKeybinds.loadGeneration;
        const restored = DisabledKeybinds.restore("main:Snip");
        verify(restored.ok, "restore failed: " + restored.error);
        waitForSave(generation);

        compare(testCase.overlay().disabled.length, 0,
            "the restored id is still disabled in the overlay");
        compare(testCase.entryFor("main:Snip"), undefined);
        verify(!DisabledKeybinds.isDisabled("main:Snip"));
        compare(testCase.fileText(testCase.mainPath), original);
    }

    function test_restore_of_an_unknown_id_does_not_write() {
        const before = KeybindStore.renderOverlay(testCase.overlay());
        const result = DisabledKeybinds.restore("never-disabled");
        verify(!result.ok, "restoring an unknown id must fail");
        compare(result.error, "not-found");
        compare(KeybindStore.renderOverlay(testCase.overlay()), before,
            "an unknown id must not write to the overlay");
        compare(testCase.fileText(testCase.mainPath), testCase.mainText());
    }

    function test_grouped_binds_are_tracked_under_one_row() {
        const generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "main:Multi", "Multi",
            [
                testCase.bind("utilities", "", ["SUPER", "SHIFT"], "S"),
                testCase.bind("utilities-2", "", ["SUPER"], "A")
            ]);
        verify(result.ok, "grouped disable failed: " + result.error);
        waitForSave(generation);

        const disabled = testCase.overlay().disabled;
        compare(disabled.length, 2);
        verify(disabled.includes("utilities") && disabled.includes("utilities-2"));
        compare(DisabledKeybinds.disabled.filter(entry => entry.id === "main:Multi").length, 2,
            "both binds must be listed under the single row id");
        compare(testCase.fileText(testCase.mainPath), testCase.mainText());
    }

    function test_disable_clears_the_override_for_the_disabled_action() {
        const action = "zzDisabledKeybindsTestAction";
        HyprlandBindOverrides.setOverride(action, "SUPER + F12");
        verify(HyprlandBindOverrides.isOverridden(action), "the test override was not set");

        const generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "main:Snip", "Screen snip", [testCase.bind("utilities", action, [], "")]);
        verify(result.ok, "disableBinds failed: " + result.error);
        waitForSave(generation);

        verify(!HyprlandBindOverrides.isOverridden(action),
            "the action's override survived the disable and could re-enable the combo");
        compare(HyprlandBindOverrides.comboFor(action, "fallback"), "fallback");
    }

    function test_main_and_custom_binds_are_handled_independently() {
        let generation = DisabledKeybinds.loadGeneration;
        const first = DisabledKeybinds.disableBinds(
            "main:Snip", "Screen snip", [testCase.bind("utilities", "", [], "")]);
        verify(first.ok, "main disable failed: " + first.error);
        waitForSave(generation);

        generation = DisabledKeybinds.loadGeneration;
        const second = DisabledKeybinds.disableBinds(
            "custom:Edit", "Edit keybinds", [testCase.bind("bind-28", "", [], "")]);
        verify(second.ok, "custom disable failed: " + second.error);
        waitForSave(generation);

        // Both writes are async FileView saves; a stale watch can briefly
        // serve the previous overlay. Wait for the file to show both ids.
        tryVerify(() => {
            const disabled = testCase.overlay().disabled;
            return disabled.includes("utilities") && disabled.includes("bind-28");
        }, 5000, "the overlay must disable both the main and the custom id, file="
            + JSON.stringify(testCase.overlay().disabled) + " mem="
            + JSON.stringify(ManagedKeybinds.overlay?.disabled));
        tryVerify(() => testCase.entryFor("main:Snip")?.file === "main", 5000,
            "the main row never appeared in the Deleted section");
        tryVerify(() => testCase.entryFor("custom:Edit")?.file === "custom", 5000,
            "the custom row never appeared in the Deleted section");
        compare(testCase.fileText(testCase.mainPath), testCase.mainText());
        compare(testCase.fileText(testCase.customPath), testCase.customText());
    }

    function test_two_binds_in_one_file_restore_together() {
        const original = testCase.mainText();
        let generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "main:Grouped", "Grouped",
            [
                testCase.bind("utilities", "actionTerm", [], ""),
                testCase.bind("utilities-3", "actionBrowser", [], "")
            ]);
        verify(result.ok, "two binds in one row failed: " + result.error);
        waitForSave(generation);

        const disabled = testCase.overlay().disabled;
        compare(disabled.length, 2);
        compare(DisabledKeybinds.disabled.filter(entry => entry.id === "main:Grouped").length, 2,
            "both binds must be offered as one grouped row");
        compare(testCase.fileText(testCase.mainPath), original);

        generation = DisabledKeybinds.loadGeneration;
        const restored = DisabledKeybinds.restore("main:Grouped");
        verify(restored.ok, "restore of the grouped id failed: " + restored.error);
        waitForSave(generation);

        tryVerify(() => testCase.overlay().disabled.length === 0, 5000,
            "restore must re-enable both ids in one save");
        tryVerify(() => testCase.entryFor("main:Grouped") === undefined, 5000,
            "the restored row must leave the Deleted section");
        compare(testCase.fileText(testCase.mainPath), original);
    }

    function test_unknown_bind_id_is_rejected_without_writing() {
        const before = KeybindStore.renderOverlay(testCase.overlay());
        const result = DisabledKeybinds.disableBinds(
            "main:Terminal", "Terminal",
            [{ sourcePath: testCase.tempDir + "/elsewhere.lua", line: 2, endLine: 2,
               action: "", comment: "Terminal" }]);
        verify(!result.ok, "a bind without a catalog id must be rejected");
        compare(result.error, "unknown-path");
        compare(KeybindStore.renderOverlay(testCase.overlay()), before,
            "a rejected bind must not write to the overlay");
        compare(testCase.fileText(testCase.mainPath), testCase.mainText());
        compare(testCase.fileText(testCase.customPath), testCase.customText());
    }

    function test_restore_clears_a_shared_id_from_both_files_in_one_cycle() {
        let generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "shared:restore", "Shared",
            [
                testCase.bind("utilities", "", [], ""),
                testCase.bind("bind-28", "", [], "")
            ]);
        verify(result.ok, "grouped disable failed: " + result.error);
        waitForSave(generation);

        compare(DisabledKeybinds.disabled.filter(entry => entry.id === "shared:restore").length, 2,
            "both binds must be listed in the Deleted section");

        generation = DisabledKeybinds.loadGeneration;
        const restored = DisabledKeybinds.restore("shared:restore");
        verify(restored.ok, "restore of the shared id failed: " + restored.error);
        waitForSave(generation);

        // restore() rebuilds the list before the async save/reload lands, so
        // the Deleted section can briefly still show the restored entries.
        tryVerify(() => testCase.overlay().disabled.length === 0, 5000,
            "one restore must re-enable the ids from both files");
        tryVerify(() => DisabledKeybinds.disabled.length === 0, 5000,
            "one restore must empty the Deleted section");
        verify(!DisabledKeybinds.isDisabled("shared:restore"));
        compare(testCase.fileText(testCase.mainPath), testCase.mainText());
        compare(testCase.fileText(testCase.customPath), testCase.customText());
    }

    function test_disable_clears_a_plain_bind_override() {
        // Plain binds have no action; OtherBindRow keys their override by
        // "bind_<combo>". A stale one would silently re-apply on restore.
        const combo = "SUPER + T";
        const overrideId = "bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_");
        HyprlandBindOverrides.setOverride(overrideId, "SUPER + Y");
        verify(HyprlandBindOverrides.isOverridden(overrideId),
            "the plain-bind test override was not set");

        const generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "main:Plain", "Terminal",
            [testCase.bind("utilities", "", ["SUPER"], "T")]);
        verify(result.ok, "plain-bind disable failed: " + result.error);
        waitForSave(generation);

        verify(!HyprlandBindOverrides.isOverridden(overrideId),
            "the bind_<combo> override survived the delete and could re-apply");
        compare(HyprlandBindOverrides.comboFor(overrideId, "fallback"), "fallback");
    }
}
