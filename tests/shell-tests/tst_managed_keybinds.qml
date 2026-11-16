import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services

/**
 * The write path of the keybind manager: a keybind created in the settings
 * form has to reach the file inside the managed markers, or the reload
 * finds nothing and the bind never takes effect.
 *
 * The test points the singleton at a temp file, so the user's real
 * keybinds.lua is never touched. The file is seeded with user content on
 * every run — including a line after the markers — because preserving
 * exactly that content is the contract of the managed block.
 *
 * Every step waits for the chain instead of assuming it is synchronous:
 * the seed through the write process, the saves through the service's load
 * counter (the FileView bumps it when a save has been read back), and the
 * file content through a reader that is created fresh for every read, so
 * no assertion can pass or fail on a stale watch.
 */
TestCase {
    id: testCase
    name: "ManagedKeybinds"
    when: true

    readonly property string tempDir: "/tmp/opencode/tst_managed_keybinds"
    readonly property string tempPath: tempDir + "/keybinds.lua"
    readonly property string startMarker: "-- >>> end4-pC managed keybinds >>>"
    readonly property string endMarker: "-- <<< end4-pC managed keybinds <<<"

    property string originalPath: ""
    property bool seedDone: false
    property bool readerLoaded: false
    property var reader: null

    // The user's own file content: a bind before the block, an empty block
    // the panel may take over, and a line after it. Every test must find
    // the two user lines untouched after its write.
    function userText() {
        return "-- user line before\n"
            + "hl.bind(\"SUPER + U\", hl.dsp.exec_cmd(\"user-command\"), {description = \"User bind\"})\n"
            + testCase.startMarker + "\n"
            + testCase.endMarker + "\n"
            + "-- user line after\n";
    }

    function seed() {
        testCase.seedDone = false;
        seedProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\"",
            "seed", testCase.tempDir, testCase.userText(), testCase.tempPath];
        seedProc.running = true;
        tryCompare(testCase, "seedDone", true, 5000, "the seed file was never written");
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

    // Waits until the write chain has finished AND the service has read
    // the save back (its FileView bumps loadGeneration on every load,
    // which includes the reload after a save), so the file on disk is
    // final when the caller reads it.
    function waitForSave(generationBefore) {
        tryCompare(ManagedKeybinds, "pendingWrite", false, 5000,
            "the write chain never finished");
        tryVerify(() => ManagedKeybinds.loadGeneration > generationBefore, 5000,
            "the save never landed (loadGeneration stayed at " + generationBefore + ")");
    }

    // A fresh reader for every read: created with its path in the creation
    // properties so the load starts with a real path, and waited for until
    // it has actually read the file.
    function fileText() {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        testCase.readerLoaded = false;
        testCase.reader = readerComponent.createObject(testCase, { "path": testCase.tempPath });
        tryCompare(testCase, "readerLoaded", true, 5000, "the reader never loaded the file");
        return testCase.reader.text();
    }

    function verifyUserContentPreserved(text) {
        verify(text.includes("-- user line before"), "the user line before the block is gone");
        verify(text.includes("user-command"), "the user bind outside the markers is gone");
        verify(text.includes("-- user line after"), "the user line after the block is gone");
    }

    function init() {
        if (testCase.originalPath === "")
            testCase.originalPath = ManagedKeybinds.keybindsPath;

        seed();
        tryCompare(ManagedKeybinds, "pendingWrite", false, 5000);

        // Force a re-read of the seeded file from disk: on the first run
        // the singleton still points at the real path, so a single switch
        // loads the seed; afterwards it already points at the temp file, so
        // hop away and back to make the load happen for real instead of
        // trusting the change watch.
        if (ManagedKeybinds.keybindsPath === testCase.originalPath) {
            const generation = ManagedKeybinds.loadGeneration;
            ManagedKeybinds.keybindsPath = testCase.tempPath;
            tryVerify(() => ManagedKeybinds.loadGeneration > generation, 5000,
                "the switch to the temp file never loaded");
        } else {
            let generation = ManagedKeybinds.loadGeneration;
            ManagedKeybinds.keybindsPath = testCase.originalPath;
            tryVerify(() => ManagedKeybinds.loadGeneration > generation, 5000,
                "the hop back to the original path never loaded");
            generation = ManagedKeybinds.loadGeneration;
            ManagedKeybinds.keybindsPath = testCase.tempPath;
            tryVerify(() => ManagedKeybinds.loadGeneration > generation, 5000,
                "the switch to the temp file never loaded");
        }

        compare(ManagedKeybinds.entries.length, 0,
            "the seeded file must parse to no managed entries");
    }

    function cleanupTestCase() {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        // Point the singleton back at the real file first, so it is not
        // left watching a path the next line deletes.
        if (testCase.originalPath !== "")
            ManagedKeybinds.keybindsPath = testCase.originalPath;
        Quickshell.execDetached(["rm", "-rf", testCase.tempDir]);
    }

    function test_create_writes_inside_the_markers_and_keeps_user_content() {
        const generation = ManagedKeybinds.loadGeneration;
        const created = ManagedKeybinds.create({
            name: "Test bind",
            category: "Utilities",
            command: "true",
            combo: "SUPER + F12"
        });
        verify(created.ok, "create failed: " + created.error);
        waitForSave(generation);
        verify(ManagedKeybinds.wrote, "the write chain never ran");

        const text = fileText();
        verify(text.includes("hl.bind(\"SUPER + F12\", hl.dsp.exec_cmd(\"true\"), {description = \"Test bind\"})"),
            "the keybind line was not written verbatim:\n" + text);
        verifyUserContentPreserved(text);
        verify(text.includes(testCase.startMarker), "no start marker");
        verify(text.includes(testCase.endMarker), "no end marker");
        verify(text.includes("--##! Utilities"), "the category heading was not written");
        verify(text.includes("-- panel-id: " + created.id), "the entry id was not written");

        // The bind must be offered back to the form with its fields.
        const found = ManagedKeybinds.editableEntries.find(entry => entry.id === created.id);
        verify(found !== undefined, "the new entry is not in editableEntries");
        compare(found.name, "Test bind");
        compare(found.category, "Utilities");
        compare(found.combo, "SUPER + F12");
    }

    function test_create_rejects_an_invalid_entry_without_writing() {
        const wroteBefore = ManagedKeybinds.wrote;
        const entriesBefore = ManagedKeybinds.entries.length;

        const created = ManagedKeybinds.create({
            name: "Say \"hi\"",
            category: "",
            command: "true",
            combo: "SUPER + F12"
        });
        verify(!created.ok, "a name with a double quote must not save");
        compare(created.error, "quote-name");

        // create() sets pendingWrite synchronously when it writes, so a
        // still-false flag proves the write chain was never entered.
        compare(ManagedKeybinds.pendingWrite, false, "a rejected entry must not write");
        compare(ManagedKeybinds.wrote, wroteBefore, "the write chain must not run");
        compare(ManagedKeybinds.entries.length, entriesBefore, "a rejected entry must not enter the block");
    }

    function test_validate_reports_the_store_code() {
        compare(ManagedKeybinds.validate({ name: "Ok", category: "", command: "true", combo: "SUPER + K" }), "");
        compare(ManagedKeybinds.validate({ name: "", category: "", command: "true", combo: "SUPER + K" }), "empty-name");
        compare(ManagedKeybinds.validate({ name: "A", category: "", command: "", combo: "SUPER + K" }), "empty-command");
        compare(ManagedKeybinds.validate({ name: "A", category: "", command: "true", combo: "" }), "empty-combo");
    }

    function test_update_changes_only_the_target_line() {
        let generation = ManagedKeybinds.loadGeneration;
        const first = ManagedKeybinds.create({
            name: "First", category: "", command: "true", combo: "SUPER + F12"
        });
        verify(first.ok, "create failed: " + first.error);
        waitForSave(generation);
        verify(fileText().includes("First"), "the first keybind never reached the file");

        generation = ManagedKeybinds.loadGeneration;
        const second = ManagedKeybinds.create({
            name: "Second", category: "", command: "false", combo: "SUPER + F11"
        });
        verify(second.ok, "create failed: " + second.error);
        waitForSave(generation);
        verify(fileText().includes("Second"), "the second keybind never reached the file");

        generation = ManagedKeybinds.loadGeneration;
        const updated = ManagedKeybinds.update(first.id, { name: "Renamed", combo: "SUPER + F10" });
        verify(updated.ok, "update failed: " + updated.error);
        waitForSave(generation);

        const text = fileText();
        verify(text.includes("description = \"Renamed\""), "the rename never reached the file:\n" + text);
        verify(text.includes("hl.bind(\"SUPER + F10\""), "the new combo did not reach the file");
        verify(!text.includes("description = \"First\""), "the old name is still there");
        verify(text.includes("description = \"Second\""), "the untouched neighbour was lost");
        verifyUserContentPreserved(text);
    }

    function test_remove_drops_the_entry_but_not_the_user_content() {
        let generation = ManagedKeybinds.loadGeneration;
        const created = ManagedKeybinds.create({
            name: "Doomed", category: "", command: "true", combo: "SUPER + F12"
        });
        verify(created.ok, "create failed: " + created.error);
        waitForSave(generation);
        verify(fileText().includes("Doomed"), "the keybind never reached the file");

        generation = ManagedKeybinds.loadGeneration;
        const removed = ManagedKeybinds.remove(created.id);
        verify(removed.ok, "remove failed: " + removed.error);
        waitForSave(generation);

        const text = fileText();
        verify(!text.includes("Doomed"), "the entry is still in the file:\n" + text);
        verify(!text.includes("-- panel-id: " + created.id), "the id comment is still in the file");
        verifyUserContentPreserved(text);
        verify(text.includes(testCase.startMarker), "the managed block itself must stay");
    }

    function test_update_and_remove_report_unknown_ids() {
        const entriesBefore = ManagedKeybinds.entries.length;

        const updated = ManagedKeybinds.update("does-not-exist", { name: "x", command: "y", combo: "z" });
        verify(!updated.ok);
        compare(updated.error, "not-found");

        const removed = ManagedKeybinds.remove("does-not-exist");
        verify(!removed.ok);
        compare(removed.error, "not-found");

        compare(ManagedKeybinds.pendingWrite, false, "an unknown id must not write");
        compare(ManagedKeybinds.entries.length, entriesBefore, "an unknown id must not change the block");
    }
}
