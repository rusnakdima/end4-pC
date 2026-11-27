import QtQuick
import QtTest
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

    property var savedOverlay: null
    property var savedEntries: null

    function init() {
        testCase.savedOverlay = ManagedKeybinds.overlay;
        testCase.savedEntries = ManagedKeybinds.entries;
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
