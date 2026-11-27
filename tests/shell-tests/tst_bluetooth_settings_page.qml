import QtQuick
import QtTest
import qs.services

TestCase {
    id: testCase
    name: "BluetoothSettingsPage"
    when: true

    property var page: null

    function init() {
        const component = Qt.createComponent("modules/ii/settings/pages/BluetoothConfig.qml");
        compare(component.status, Component.Ready,
            "Bluetooth page failed to load: " + component.errorString());
        testCase.page = component.createObject(null);
        verify(testCase.page !== null, "Bluetooth page failed to instantiate");
    }

    function cleanup() {
        if (testCase.page !== null) testCase.page.destroy();
        testCase.page = null;
    }

    function test_page_has_the_three_bluetooth_sections() {
        verify(testCase.page.bluetoothSectionItem !== null, "the Bluetooth section is missing");
        verify(testCase.page.pairedSectionItem !== null, "the Paired devices section is missing");
        verify(testCase.page.nearbySectionItem !== null, "the Nearby devices section is missing");
    }

    function test_page_has_an_enable_switch_bound_to_the_service() {
        const toggle = testCase.page.enabledSwitchItem;
        verify(toggle !== null, "the Bluetooth switch is missing");
        compare(toggle.checked, BluetoothStatus.enabled);
    }

    function test_empty_state_is_shown_when_there_are_no_devices() {
        const empty = testCase.page.emptyStateItem;
        verify(empty !== null, "the empty-state label is missing");
        if (BluetoothStatus.friendlyDeviceList.length === 0)
            verify(empty.visible, "an empty device list must show the empty state");
    }

    function test_connect_pair_and_forget_actions_are_exposed() {
        verify(typeof testCase.page.connectDevice === "function", "no connect action");
        verify(typeof testCase.page.pairDevice === "function", "no pair action");
        verify(typeof testCase.page.forgetDevice === "function", "no forget action");
    }
}
