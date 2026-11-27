import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import "modules/common/functions/KeybindStore.js" as KeybindStore

/**
 * The Default apps pane shows one list: built-in roles from the JSON catalog
 * plus apps the user added through the keybind overlay. No live config is
 * touched — the add is injected into the singleton's in-memory view.
 */
TestCase {
    id: testCase
    name: "DefaultAppsRows"
    when: true

    readonly property string tempDir: "/tmp/end4pc-shell-tests/tst_default_apps_rows"
    readonly property string tempPath: tempDir + "/keybind-overlay.json"

    property var savedOverlay: null
    property var savedEntries: null
    property string savedPath: ""
    property string generatorOutput: ""
    property string readerText: ""
    property bool readerLoaded: false
    property var reader: null

    function init() {
        testCase.savedOverlay = ManagedKeybinds.overlay;
        testCase.savedEntries = ManagedKeybinds.entries;
        testCase.savedPath = ManagedKeybinds.keybindsPath;
        const add = KeybindStore.makeAdd({
            name: "Test App",
            category: "Apps",
            combo: "SUPER + ALT + T",
            command: "testapp --flag"
        }, "test-app-1");
        ManagedKeybinds.overlay = KeybindStore.withAdds(KeybindStore.newOverlay(), [add]);
        ManagedKeybinds.entries = [KeybindStore.addToEntry(add)];
    }

    function cleanup() {
        ManagedKeybinds.overlay = testCase.savedOverlay;
        ManagedKeybinds.entries = testCase.savedEntries;
        ManagedKeybinds.keybindsPath = testCase.savedPath;
    }

    // Writes go through FileView.setText -> generator Process. Let both
    // finish before a test restores the live path, or a late setText can land
    // in the next test's overlay file.
    function settleWrites() {
        tryCompare(ManagedKeybinds, "awaitGeneration", false, 5000);
        settleProc.command = ["sh", "-c",
            "while pgrep -f '[g]enerate_keybinds.py' >/dev/null 2>&1; do sleep 0.05; done"];
        settleProc.running = true;
        tryCompare(settleProc, "running", false, 5000);
    }

    function readFile(path) {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        testCase.readerLoaded = false;
        testCase.readerText = "";
        testCase.reader = readerComponent.createObject(testCase, { "path": path });
        tryCompare(testCase, "readerLoaded", true, 5000, "could not read " + path);
        return testCase.readerText;
    }

    Component {
        id: readerComponent
        FileView {
            preload: true
            onLoaded: {
                testCase.readerText = text();
                testCase.readerLoaded = true;
            }
        }
    }

    function test_add_app_creates_row_and_generated_bind() {
        const component = Qt.createComponent("modules/ii/settings/pages/DefaultAppsConfig.qml");
        compare(component.status, Component.Ready, "Default apps page failed to load: " + component.errorString());
        const page = component.createObject(null);
        verify(page !== null, "Default apps page failed to instantiate");
        verify(typeof page.addApp === "function", "the Default apps page has no Add app helper");

        seedProc.command = ["sh", "-c", "mkdir -p \"$1\" && printf '%s' > \"$2\"",
            "seed", testCase.tempDir, testCase.tempPath];
        seedProc.running = true;
        tryCompare(seedProc, "running", false, 5000);
        ManagedKeybinds.keybindsPath = testCase.tempPath;

        const result = page.addApp("My App", "myapp --flag %f", "SUPER + SHIFT + M");
        verify(result.ok, "addApp failed: " + result.error);
        const rows = DefaultApps.appRows.filter(row => row.id === result.id);
        compare(rows.length, 1);
        compare(rows[0].custom, true);
        compare(rows[0].label, "My App");
        compare(rows[0].command, "myapp --flag");
        compare(rows[0].combo, "SUPER + SHIFT + M");

        generatorProc.command = ["python3", ManagedKeybinds.generatorPath,
            "--catalog", ManagedKeybinds.catalogPath,
            "--overlay", testCase.tempPath,
            "--main-out", testCase.tempDir + "/main.lua",
            "--custom-out", testCase.tempDir + "/custom.lua",
            "--commands-out", testCase.tempDir + "/commands.json"];
        generatorProc.running = true;
        tryCompare(generatorProc, "running", false, 10000);
        verify(testCase.generatorOutput.includes("generated "),
            "generator did not report success: " + testCase.generatorOutput);
        const lua = readFile(testCase.tempDir + "/custom.lua");
        verify(lua.includes("quickshell:runCommand:" + result.id),
            "the added app is missing from generated Lua");
        const commands = JSON.parse(readFile(testCase.tempDir + "/commands.json"));
        compare(commands[result.id].command, "myapp --flag");

        settleWrites();
        page.destroy();
    }

    Process {
        id: seedProc
        onExited: {}
    }

    function test_rebinding_builtin_and_custom_rows() {
        const component = Qt.createComponent("modules/ii/settings/pages/DefaultAppsConfig.qml");
        compare(component.status, Component.Ready, "Default apps page failed to load: " + component.errorString());
        const page = component.createObject(null);
        verify(page !== null, "Default apps page failed to instantiate");
        verify(typeof page.setCombo === "function", "the Default apps page has no setCombo helper");

        seedProc.command = ["sh", "-c", "mkdir -p \"$1\" && printf '%s' > \"$2\"",
            "seed", testCase.tempDir, testCase.tempPath];
        seedProc.running = true;
        tryCompare(seedProc, "running", false, 5000);
        ManagedKeybinds.keybindsPath = testCase.tempPath;

        const builtin = DefaultApps.appRows.find(row => row.id === "terminal");
        verify(builtin !== undefined, "the terminal row is missing");
        const builtinResult = page.setCombo(builtin, "SUPER + ALT + B");
        verify(builtinResult.ok, "built-in rebind failed: " + builtinResult.error);
        verify(ManagedKeybinds.isOverridden("apps"), "the terminal bind was not overridden");
        const builtinAfter = DefaultApps.appRows.find(row => row.id === "terminal");
        compare(builtinAfter.combo, "SUPER + ALT + B");

        const custom = DefaultApps.appRows.find(row => row.custom === true);
        verify(custom !== undefined, "the custom row is missing");
        const customResult = page.setCombo(custom, "SUPER + CTRL + B");
        verify(customResult.ok, "custom rebind failed: " + customResult.error);
        const customAfter = DefaultApps.appRows.find(row => row.id === custom.id);
        compare(customAfter.combo, "SUPER + CTRL + B");

        settleWrites();
        page.destroy();
    }

    Process {
        id: settleProc
        onExited: {}
    }

    Process {
        id: generatorProc
        stdout: StdioCollector { onStreamFinished: testCase.generatorOutput = text }
        stderr: StdioCollector { onStreamFinished: testCase.generatorOutput += text }
    }

    function test_builtin_roles_are_all_present_once() {
        const builtins = DefaultApps.appRows.filter(row => row.custom === false);
        compare(builtins.length, 8);
        const ids = builtins.map(row => row.id).join(",");
        compare(ids, "terminal,filemanager,browser,codeeditor,office,texteditor,volumemixer,taskmanager");
    }

    function test_an_overlay_add_appears_as_a_custom_app_row() {
        const rows = DefaultApps.appRows.filter(row => row.custom === true);
        compare(rows.length, 1);
        compare(rows[0].id, "test-app-1");
        compare(rows[0].label, "Test App");
        compare(rows[0].command, "testapp --flag");
        compare(rows[0].combo, "SUPER + ALT + T");
        compare(rows[0].bindIds.join(","), "test-app-1");
    }
}
