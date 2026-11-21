import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services

/**
 * The write path of the recoverable "delete keybind" feature.
 *
 * The service owns two config files. Both are pointed at temporary files
 * here, so the real hyprland/keybinds.lua and custom/keybinds.lua are never
 * touched. Every test reseeds the files, which proves that a write only
 * changes the targeted lines and that restore puts the exact bytes back.
 *
 * The FileView save chain is asynchronous, so each write is followed by a
 * wait on the service's load counter. File contents are read through a fresh
 * reader every time, so no assertion can pass on a stale watch.
 */
TestCase {
    id: testCase
    name: "DisabledKeybinds"
    when: true

    readonly property string tempDir: "/tmp/opencode/tst_disabled_keybinds"
    readonly property string mainPath: tempDir + "/hyprland-keybinds.lua"
    readonly property string customPath: tempDir + "/custom-keybinds.lua"

    property string originalMainPath: ""
    property string originalCustomPath: ""
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

    function multilineText() {
        return "-- custom head\n"
            + "hl.bind(\"SUPER + M\",\n"
            + "  hl.dsp.exec_cmd(\"one; two; three\"),\n"
            + "  {description = \"Multi\"})\n"
            + "-- custom tail\n";
    }

    function terminalLine() {
        return "hl.bind(\"SUPER + T\", hl.dsp.exec_cmd(\"kitty\"), {description = \"Terminal\"})";
    }

    function startLine(id) { return "-- >>> end4-pC disabled keybind: " + id; }
    function endLine() { return "-- <<< end4-pC disabled keybind <<<"; }

    function seed(text) {
        testCase.seedDone = false;
        seedProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\"",
            "seed", testCase.tempDir, text, testCase.mainPath];
        seedProc.running = true;
        tryCompare(testCase, "seedDone", true, 5000, "the main seed was never written");
    }

    function seedBoth(main, custom) {
        testCase.seedDone = false;
        seedProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\" && printf '%s' \"$4\" > \"$5\"",
            "seed", testCase.tempDir, main, testCase.mainPath, custom, testCase.customPath];
        seedProc.running = true;
        tryCompare(testCase, "seedDone", true, 5000, "the seed was never written");
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

    function waitForSave(generationBefore) {
        tryCompare(DisabledKeybinds, "pendingSaves", 0, 5000,
            "the FileView save never finished");
        tryVerify(() => DisabledKeybinds.loadGeneration > generationBefore, 5000,
            "the save never landed (loadGeneration stayed at " + generationBefore + ")");
    }

    // An external re-seed is invisible to the service until its FileView
    // actually reads it. Hop away and back so the next edit cannot splice
    // against the bytes the service saw before the re-seed.
    function forceReread() {
        const main = DisabledKeybinds.defaultKeybindConfigPath;
        const custom = DisabledKeybinds.userKeybindConfigPath;
        const generation = DisabledKeybinds.loadGeneration;
        DisabledKeybinds.defaultKeybindConfigPath = testCase.originalMainPath;
        DisabledKeybinds.userKeybindConfigPath = testCase.originalCustomPath;
        tryVerify(() => DisabledKeybinds.loadGeneration > generation, 5000,
            "the hop away never loaded");
        const away = DisabledKeybinds.loadGeneration;
        DisabledKeybinds.defaultKeybindConfigPath = main;
        DisabledKeybinds.userKeybindConfigPath = custom;
        tryVerify(() => DisabledKeybinds.loadGeneration > away, 5000,
            "the hop back never loaded");
    }

    // Reseed and force a real re-read. On the first test the singleton still
    // points at the real paths; afterwards hop away and back so the change
    // watch cannot hand us stale bytes from the previous run.
    function init() {
        if (testCase.originalMainPath === "")
            testCase.originalMainPath = DisabledKeybinds.defaultKeybindConfigPath;
        if (testCase.originalCustomPath === "")
            testCase.originalCustomPath = DisabledKeybinds.userKeybindConfigPath;

        seedBoth(testCase.mainText(), testCase.customText());

        const generation = DisabledKeybinds.loadGeneration;
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
        tryVerify(() => DisabledKeybinds.ready
            && DisabledKeybinds.loadGeneration >= generation + 2, 5000,
            "the service never loaded both seeded files");
    }

    function cleanup() {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        // Leave no test override behind for the real overrides file.
        if (HyprlandBindOverrides.isOverridden("zzDisabledKeybindsTestAction"))
            HyprlandBindOverrides.clearOverride("zzDisabledKeybindsTestAction");
        const plainOverrideId = "bind_" + "SUPER + T".replace(/[^A-Za-z0-9_]/g, "_");
        if (HyprlandBindOverrides.isOverridden(plainOverrideId))
            HyprlandBindOverrides.clearOverride(plainOverrideId);
    }

    function cleanupTestCase() {
        if (testCase.originalMainPath !== "") {
            DisabledKeybinds.defaultKeybindConfigPath = testCase.originalMainPath;
            DisabledKeybinds.userKeybindConfigPath = testCase.originalCustomPath;
        }
        Quickshell.execDetached(["rm", "-rf", testCase.tempDir]);
    }

    function bindAt(path, line, endLine, action, comment) {
        return {
            sourcePath: path, line: line, endLine: endLine,
            action: action, comment: comment
        };
    }

    function entryFor(id) {
        return DisabledKeybinds.disabled.find(entry => entry.id === id);
    }

    function test_disable_one_line_writes_marker_and_updates_state() {
        const generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "main:Terminal", "Terminal",
            [testCase.bindAt(testCase.mainPath, 2, 2, "actionTerm", "Terminal")]);
        verify(result.ok, "disableBinds failed: " + result.error);
        waitForSave(generation);

        const text = testCase.fileText(testCase.mainPath);
        verify(text.includes(testCase.startLine("main:Terminal")), "no start marker:\n" + text);
        verify(text.includes("-- " + testCase.terminalLine()), "the bind line was not commented:\n" + text);
        verify(text.includes(testCase.endLine()), "no end marker:\n" + text);
        verify(text.includes("-- main head") && text.includes("-- main tail"), "a user line was lost");
        verify(text.includes("hl.bind(\"SUPER + B\""), "the untouched neighbour was lost");

        const entry = testCase.entryFor("main:Terminal");
        verify(entry !== undefined, "disabled did not get the new entry");
        compare(entry.label, "Terminal");
        compare(entry.file, "main");
        compare(entry.lines.length, 1);
        compare(entry.lines[0], testCase.terminalLine());
        verify(DisabledKeybinds.isDisabled("main:Terminal"));
        verify(!DisabledKeybinds.isDisabled("main:Missing"));
    }

    function test_restore_returns_the_original_bytes() {
        const original = testCase.mainText();
        let generation = DisabledKeybinds.loadGeneration;
        const removed = DisabledKeybinds.disableBinds(
            "main:Terminal", "Terminal",
            [testCase.bindAt(testCase.mainPath, 2, 2, "actionTerm", "Terminal")]);
        verify(removed.ok, "disableBinds failed: " + removed.error);
        waitForSave(generation);

        generation = DisabledKeybinds.loadGeneration;
        const restored = DisabledKeybinds.restore("main:Terminal");
        verify(restored.ok, "restore failed: " + restored.error);
        waitForSave(generation);

        compare(testCase.fileText(testCase.mainPath), original);
        compare(testCase.entryFor("main:Terminal"), undefined);
        verify(!DisabledKeybinds.isDisabled("main:Terminal"));
    }

    function test_restore_of_an_unknown_id_does_not_write() {
        const result = DisabledKeybinds.restore("never-disabled");
        verify(!result.ok, "restoring an unknown id must fail");
        compare(result.error, "not-found");
        compare(testCase.fileText(testCase.mainPath), testCase.mainText());
    }

    function test_disable_multiline_comments_every_line() {
        seedBoth(testCase.multilineText(), testCase.customText());
        testCase.forceReread();
        const generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "main:Multi", "Multi",
            [testCase.bindAt(testCase.mainPath, 2, 4, "actionMulti", "Multi")]);
        verify(result.ok, "disableBinds failed: " + result.error);
        waitForSave(generation);

        const text = testCase.fileText(testCase.mainPath);
        verify(text.includes(testCase.startLine("main:Multi")), "no start marker:\n" + text);
        verify(text.includes("-- hl.bind(\"SUPER + M\","), "first line not commented:\n" + text);
        verify(text.includes("--   hl.dsp.exec_cmd(\"one; two; three\"),"), "second line not commented:\n" + text);
        verify(text.includes("--   {description = \"Multi\"})"), "third line not commented:\n" + text);
        verify(text.includes(testCase.endLine()), "no end marker:\n" + text);
        compare(testCase.entryFor("main:Multi").lines.length, 3);
    }

    function test_disable_clears_the_override_for_the_disabled_action() {
        const action = "zzDisabledKeybindsTestAction";
        HyprlandBindOverrides.setOverride(action, "SUPER + F12");
        verify(HyprlandBindOverrides.isOverridden(action), "the test override was not set");

        const generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "main:Terminal", "Terminal",
            [testCase.bindAt(testCase.mainPath, 2, 2, action, "Terminal")]);
        verify(result.ok, "disableBinds failed: " + result.error);
        waitForSave(generation);

        verify(!HyprlandBindOverrides.isOverridden(action),
            "the action's override survived the disable and could re-enable the combo");
        compare(HyprlandBindOverrides.comboFor(action, "fallback"), "fallback");
    }

    function test_main_and_custom_files_are_handled_independently() {
        let generation = DisabledKeybinds.loadGeneration;
        const first = DisabledKeybinds.disableBinds(
            "main:Terminal", "Terminal",
            [testCase.bindAt(testCase.mainPath, 2, 2, "actionTerm", "Terminal")]);
        verify(first.ok, "main disable failed: " + first.error);
        waitForSave(generation);

        generation = DisabledKeybinds.loadGeneration;
        const second = DisabledKeybinds.disableBinds(
            "custom:Editor", "Editor",
            [testCase.bindAt(testCase.customPath, 2, 2, "actionEdit", "Editor")]);
        verify(second.ok, "custom disable failed: " + second.error);
        waitForSave(generation);

        const mainFileText = testCase.fileText(testCase.mainPath);
        const customFileText = testCase.fileText(testCase.customPath);
        verify(mainFileText.includes(testCase.startLine("main:Terminal")), "main marker missing");
        verify(!mainFileText.includes(testCase.startLine("custom:Editor")), "custom marker leaked into main");
        verify(customFileText.includes(testCase.startLine("custom:Editor")), "custom marker missing");
        verify(!customFileText.includes(testCase.startLine("main:Terminal")), "main marker leaked into custom");
        compare(testCase.entryFor("main:Terminal").file, "main");
        compare(testCase.entryFor("custom:Editor").file, "custom");
    }

    function test_grouped_files_produce_one_reload_not_one_per_file() {
        const generation = DisabledKeybinds.loadGeneration;
        const reloads = DisabledKeybinds.reloadCount;
        const result = DisabledKeybinds.disableBinds(
            "shared:bind", "Shared",
            [
                testCase.bindAt(testCase.mainPath, 2, 2, "", "Terminal"),
                testCase.bindAt(testCase.customPath, 2, 2, "", "Editor")
            ]);
        verify(result.ok, "grouped disable failed: " + result.error);
        waitForSave(generation);

        verify(testCase.fileText(testCase.mainPath).includes(testCase.startLine("shared:bind")),
            "the main bind was not disabled");
        verify(testCase.fileText(testCase.customPath).includes(testCase.startLine("shared:bind")),
            "the custom bind was not disabled");
        compare(DisabledKeybinds.reloadCount, reloads + 1,
            "two files in one save must trigger exactly one hyprctl reload");
    }

    function test_two_binds_in_one_file_write_once_and_restore_both() {
        // The regression case: two binds share sourcePath and the caller's
        // single id. They must become two blocks in one file, produced by one
        // write and one reload, and restore must bring both lines back.
        const original = testCase.mainText();
        const generation = DisabledKeybinds.loadGeneration;
        const writes = DisabledKeybinds.writeCount;
        const reloads = DisabledKeybinds.reloadCount;

        const result = DisabledKeybinds.disableBinds(
            "main:Grouped", "Grouped",
            [
                testCase.bindAt(testCase.mainPath, 2, 2, "actionTerm", "Terminal"),
                testCase.bindAt(testCase.mainPath, 3, 3, "actionBrowser", "Browser")
            ]);
        verify(result.ok, "two binds in one file failed: " + result.error);
        waitForSave(generation);

        const text = testCase.fileText(testCase.mainPath);
        compare((text.match(/-- >>> end4-pC disabled keybind: main:Grouped/g) || []).length, 2,
            "one marker per bind was expected");
        verify(text.includes("-- " + testCase.terminalLine()), "the first bind was not commented");
        verify(text.includes("-- hl.bind(\"SUPER + B\", hl.dsp.exec_cmd(\"firefox\"), {description = \"Browser\"})"),
            "the second bind was not commented");
        verify(text.includes("-- main head") && text.includes("-- main tail"), "a user line was lost");

        const grouped = DisabledKeybinds.disabled.filter(entry => entry.id === "main:Grouped");
        compare(grouped.length, 2, "both blocks must be exposed to the pane");
        compare(grouped[0].file, "main");
        compare(grouped[1].file, "main");

        compare(DisabledKeybinds.writeCount, writes + 1,
            "two binds in one file must produce one write, not one per bind");
        compare(DisabledKeybinds.reloadCount, reloads + 1,
            "two binds in one file must produce one reload, not one per bind");

        const restoreGeneration = DisabledKeybinds.loadGeneration;
        const restored = DisabledKeybinds.restore("main:Grouped");
        verify(restored.ok, "restore of the grouped id failed: " + restored.error);
        waitForSave(restoreGeneration);

        compare(testCase.fileText(testCase.mainPath), original,
            "restore must return the exact original bytes with both binds back");
        compare(testCase.entryFor("main:Grouped"), undefined);
        verify(!DisabledKeybinds.isDisabled("main:Grouped"));
    }

    function test_unknown_source_path_is_rejected_without_writing() {
        const result = DisabledKeybinds.disableBinds(
            "main:Terminal", "Terminal",
            [testCase.bindAt(testCase.tempDir + "/elsewhere.lua", 2, 2, "", "Terminal")]);
        verify(!result.ok, "an unowned path must be rejected");
        compare(result.error, "unknown-path");
        compare(testCase.fileText(testCase.mainPath), testCase.mainText());
        compare(testCase.fileText(testCase.customPath), testCase.customText());
    }

    function test_restore_clears_a_shared_id_from_both_files_in_one_cycle() {
        // disableBinds lets one id span both files (shell actions group their
        // binds across the merged tree). Restore must do the same: stopping
        // at the first file leaves the custom block disabled forever.
        const originalMain = testCase.mainText();
        const originalCustom = testCase.customText();
        let generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds(
            "shared:restore", "Shared",
            [
                testCase.bindAt(testCase.mainPath, 2, 2, "", "Terminal"),
                testCase.bindAt(testCase.customPath, 2, 2, "", "Editor")
            ]);
        verify(result.ok, "grouped disable failed: " + result.error);
        waitForSave(generation);

        verify(testCase.fileText(testCase.mainPath).includes(testCase.startLine("shared:restore")),
            "the main block was not disabled");
        verify(testCase.fileText(testCase.customPath).includes(testCase.startLine("shared:restore")),
            "the custom block was not disabled");
        compare(DisabledKeybinds.disabled.filter(entry => entry.id === "shared:restore").length, 2,
            "both files must be listed in the Deleted section");

        generation = DisabledKeybinds.loadGeneration;
        const writes = DisabledKeybinds.writeCount;
        const reloads = DisabledKeybinds.reloadCount;
        const restored = DisabledKeybinds.restore("shared:restore");
        verify(restored.ok, "restore of the shared id failed: " + restored.error);
        waitForSave(generation);

        compare(testCase.fileText(testCase.mainPath), originalMain,
            "the main block survived restore");
        compare(testCase.fileText(testCase.customPath), originalCustom,
            "the custom block survived restore");
        compare(DisabledKeybinds.disabled.length, 0,
            "one restore must empty the Deleted section");
        verify(!DisabledKeybinds.isDisabled("shared:restore"));
        compare(DisabledKeybinds.writeCount, writes + 2,
            "one write per file in a single restore cycle");
        compare(DisabledKeybinds.reloadCount, reloads + 1,
            "both files in one restore must trigger exactly one reload");
    }

    function test_disable_clears_a_plain_bind_override() {
        // Plain binds have no action; OtherBindRow keys their override by
        // "bind_<combo>". A stale one would silently re-apply on restore.
        const combo = "SUPER + T";
        const overrideId = "bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_");
        HyprlandBindOverrides.setOverride(overrideId, "SUPER + Y");
        verify(HyprlandBindOverrides.isOverridden(overrideId),
            "the plain-bind test override was not set");

        const plainBind = Object.assign(
            testCase.bindAt(testCase.mainPath, 2, 2, "", "Terminal"),
            { mods: ["SUPER"], key: "T" });
        const generation = DisabledKeybinds.loadGeneration;
        const result = DisabledKeybinds.disableBinds("main:Plain", "Terminal", [plainBind]);
        verify(result.ok, "plain-bind disable failed: " + result.error);
        waitForSave(generation);

        verify(!HyprlandBindOverrides.isOverridden(overrideId),
            "the bind_<combo> override survived the delete and could re-apply");
        compare(HyprlandBindOverrides.comboFor(overrideId, "fallback"), "fallback");
    }
}
