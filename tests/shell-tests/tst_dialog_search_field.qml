import QtQuick
import QtTest
import qs.modules.common.widgets

/**
 * The search row that the Wi-Fi and Bluetooth dialogs embed: the text
 * alias, the placeholder pass-through, the clear button that only exists
 * while there is text, and the autofocus default.
 *
 * The harness runs without a window, so the Escape handling and the focus
 * move itself are not asserted here - they are walked on the live shell.
 */
TestCase {
    id: testCase
    name: "DialogSearchField"
    when: true

    property var field: null

    Component {
        id: fieldComponent
        DialogSearchField {}
    }

    function init() {
        testCase.field = fieldComponent.createObject(null);
    }

    function cleanup() {
        // The component queues its focus move with Qt.callLater; let that
        // run while the object still exists instead of after the destroy.
        wait(5);
        if (testCase.field !== null) {
            testCase.field.destroy();
            testCase.field = null;
        }
    }

    function clearButton() {
        const children = testCase.field.children;
        for (let i = 0; i < children.length; ++i) {
            if (children[i].objectName === "clearButton")
                return children[i];
        }
        return null;
    }

    function test_text_round_trips_through_the_alias() {
        compare(field.text, "");
        field.text = "home";
        compare(field.text, "home");
        field.text = "";
        compare(field.text, "");
    }

    function test_placeholder_is_passed_through() {
        field.placeholderText = "Search networks";
        compare(field.placeholderText, "Search networks");
    }

    function test_the_clear_button_only_exists_while_there_is_text() {
        const clear = clearButton();
        verify(clear !== null, "the clear button is missing from the row");
        compare(clear.visible, false);
        field.text = "home";
        tryVerify(() => clear.visible === true, 1000);
        field.text = "";
        tryVerify(() => clear.visible === false, 1000);
    }

    function test_autofocus_is_on_by_default() {
        compare(field.autoFocus, true);
    }
}
