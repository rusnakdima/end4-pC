import QtQuick
import QtTest
import qs.modules.common.widgets

/**
 * The spoiler header on the right sidebar's collapsible cards.
 *
 * The first assertion is the point of this file. qmllint does not report a
 * property that redeclares one the base type marks final: declaring `icon`
 * on top of Button's final `icon` group passed tests/qml-compile-check.sh
 * and only failed at engine load, which took the whole shell down on
 * reload. Creating the component here runs the same engine load, so the
 * suite fails instead of the user's desktop.
 */
TestCase {
    id: testCase
    name: "CollapsibleSectionHeader"
    when: true

    property var header: null

    Component {
        id: headerComponent
        CollapsibleSectionHeader {
            title: "Notifications"
        }
    }

    function init() {
        testCase.header = null;
        if (headerComponent.status === Component.Ready)
            testCase.header = headerComponent.createObject(null);
    }

    function cleanup() {
        if (testCase.header !== null) {
            testCase.header.destroy();
            testCase.header = null;
        }
    }

    function test_it_loads_in_the_engine() {
        compare(headerComponent.status, Component.Ready, headerComponent.errorString());
        verify(testCase.header !== null, "CollapsibleSectionHeader failed to create");
    }

    function test_it_reports_the_height_the_cards_size_from() {
        verify(testCase.header !== null, "the header did not create");
        // The collapsed notifications card is exactly this row plus its
        // margins: CenterWidgetGroup binds implicitHeight to it.
        compare(testCase.header.implicitHeight, 40);
    }

    function test_its_properties_and_signal_exist() {
        verify(testCase.header !== null, "the header did not create");
        compare(testCase.header.title, "Notifications");
        compare(typeof testCase.header.headerIcon, "string");
        compare(typeof testCase.header.trailingText, "string");
        compare(typeof testCase.header.collapsed, "boolean");
        // The card keeps its own Persistent binding precisely because the
        // header only reports the tap.
        compare(typeof testCase.header.collapseToggled, "function");
    }

    function test_the_default_state_is_expanded() {
        verify(testCase.header !== null, "the header did not create");
        compare(testCase.header.collapsed, false);
        compare(testCase.header.trailingText, "");
        compare(testCase.header.headerIcon, "");
    }
}
