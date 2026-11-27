import QtQuick
import QtTest
import qs.services

TestCase {
    id: testCase
    name: "WifiSettingsPage"
    when: true

    property var page: null

    function init() {
        const component = Qt.createComponent("modules/ii/settings/pages/WifiConfig.qml");
        compare(component.status, Component.Ready,
            "Wi-Fi page failed to load: " + component.errorString());
        testCase.page = component.createObject(null);
        verify(testCase.page !== null, "Wi-Fi page failed to instantiate");
    }

    function cleanup() {
        if (testCase.page !== null) testCase.page.destroy();
        testCase.page = null;
    }

    function test_page_has_the_three_wifi_sections() {
        verify(testCase.page.connectionSectionItem !== null, "the Connection section is missing");
        verify(testCase.page.availableSectionItem !== null, "the Available networks section is missing");
        verify(testCase.page.savedSectionItem !== null, "the Saved networks section is missing");
    }

    function test_page_has_a_wifi_toggle_bound_to_the_service() {
        const toggle = testCase.page.enabledSwitchItem;
        verify(toggle !== null, "the Wi-Fi switch is missing");
        compare(toggle.checked, Network.wifiEnabled);
    }

    function test_empty_state_is_shown_when_there_are_no_networks() {
        const empty = testCase.page.emptyStateItem;
        verify(empty !== null, "the empty-state label is missing");
        if (Network.friendlyWifiNetworks.length === 0)
            verify(empty.visible, "an empty network list must show the empty state");
    }

    function test_connect_and_forget_actions_are_exposed() {
        verify(typeof testCase.page.connectNetwork === "function",
            "the page has no connect action");
        verify(typeof testCase.page.forgetNetwork === "function",
            "the page has no forget action");
        verify(typeof testCase.page.disconnectNetwork === "function",
            "the page has no disconnect action");
    }
}
