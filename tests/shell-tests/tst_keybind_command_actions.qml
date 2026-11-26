import QtQuick
import QtTest
import qs.services

/** Command action picker: category/label derivation and form semantics. */
TestCase {
    id: testCase
    name: "KeybindCommandActions"
    when: true

    property var savedCatalog: null
    property var page: null

    function init() {
        testCase.savedCatalog = HyprlandKeybinds.catalog;
    }

    function cleanup() {
        HyprlandKeybinds.catalog = testCase.savedCatalog;
        if (testCase.page !== null) {
            testCase.page.destroy();
            testCase.page = null;
        }
    }

    function pageInstance() {
        const component = Qt.createComponent("modules/ii/settings/pages/KeyboardConfig.qml");
        verify(component.status === Component.Ready,
            "KeyboardConfig did not load: " + component.errorString());
        testCase.page = component.createObject(testCase);
        verify(testCase.page !== null, "KeyboardConfig could not be created");
        return testCase.page;
    }

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
        compare(index[0].bindId, "m1");
        compare(index[2].category, "Shell");
    }

    function test_picker_selection_fills_only_the_command() {
        const page = pageInstance();
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
    }
}
