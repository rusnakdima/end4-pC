import QtQuick
import QtTest
import qs
import qs.services

/**
 * Settings deep-links: the right pane only sets settingsTarget, and the
 * settings content is responsible for resolving it to a registered page.
 */
TestCase {
    id: testCase
    name: "SettingsDeeplink"
    when: true

    property var savedTarget: null
    property var content: null

    function openContent() {
        const component = Qt.createComponent("modules/ii/settings/SettingsContent.qml");
        compare(component.status, Component.Ready, "SettingsContent failed to load: " + component.errorString());
        testCase.content = component.createObject(null);
        verify(testCase.content !== null, "SettingsContent could not be created");
    }

    function init() {
        testCase.savedTarget = GlobalStates.settingsTarget;
        openContent();
    }

    function cleanup() {
        if (testCase.content !== null) testCase.content.destroy();
        GlobalStates.settingsTarget = testCase.savedTarget;
        GlobalStates.settingsOpen = false;
    }

    function deepLink(pageId) {
        GlobalStates.settingsTarget = { page: pageId };
        tryVerify(() => GlobalStates.settingsTarget === null, 3000);
        const expected = SettingsPages.pages.findIndex(p => p.id === pageId);
        verify(expected >= 0, pageId + " is not registered");
        compare(testCase.content.currentPage, expected);
    }

    function test_wifi_deeplink() {
        deepLink("wifi");
    }

    function test_bluetooth_deeplink() {
        deepLink("bluetooth");
    }

    function test_deeplink_works_when_settings_was_closed() {
        GlobalStates.settingsOpen = false;
        deepLink("wifi");
    }

    function test_pending_deeplink_is_consumed_when_content_is_created() {
        // The right-pane tile sets the target BEFORE the window creates the
        // settings content, so onSettingsTargetChanged never fires for it.
        testCase.content.destroy();
        testCase.content = null;
        // destroy() completes on the next event-loop turn; until then the old
        // content's Connections would consume the target before the new one
        // is created.
        wait(10);
        GlobalStates.settingsOpen = false;
        GlobalStates.settingsTarget = { page: "bluetooth" };
        openContent();
        const expected = SettingsPages.pages.findIndex(p => p.id === "bluetooth");
        verify(expected >= 0, "bluetooth is not registered");
        compare(testCase.content.currentPage, expected);
        compare(GlobalStates.settingsTarget, null);
    }
}
