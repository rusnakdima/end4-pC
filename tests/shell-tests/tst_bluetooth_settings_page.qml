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

    function test_paired_empty_state_ignores_nearby_only_devices() {
        const nearby = [{ address: "AA:BB", name: "Nearby", paired: false, connected: false }];
        testCase.page.connectedDevices = [];
        testCase.page.pairedDevices = [];
        testCase.page.nearbyDevices = nearby;
        verify(testCase.page.emptyStateItem.visible,
            "a nearby-only device must not leave the paired card blank");
        testCase.page.pairedDevices = [{ address: "CC:DD", name: "Paired", paired: true, connected: false }];
        verify(!testCase.page.emptyStateItem.visible,
            "a paired device must hide the paired empty state");
    }

    function test_action_errors_are_surfaced() {
        verify(typeof BluetoothStatus.lastActionError === "string",
            "the Bluetooth service must expose action errors");
        const label = testCase.page.errorLabelItem;
        verify(label !== null, "the page has no action-error label");
        testCase.page.actionError = "Pair failed";
        verify(label.visible, "a failed action must show an error");
        compare(label.text, "Pair failed");
    }

    function test_action_output_json_is_not_treated_as_an_error() {
        const saved = BluetoothStatus.lastActionError;
        BluetoothStatus.lastActionError = "";
        BluetoothStatus.applyActionOutput('{"available":true,"enabled":true}');
        compare(BluetoothStatus.lastActionError, "",
            "the helper's state JSON must not become an error");
        BluetoothStatus.applyActionOutput('{"available":true,"lastActionError":"Pair failed"}');
        compare(BluetoothStatus.lastActionError, "Pair failed",
            "an explicit action failure must be surfaced");
        BluetoothStatus.lastActionError = saved;
    }
}
