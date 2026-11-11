import QtQuick
import QtTest
import qs.modules.common
import qs.services
import qs.modules.common.widgets

/**
 * The per-app half of the window mode: the widget that shows the rule
 * list of the config and writes it back.
 *
 * The widget is created the way the settings page creates it, so a role
 * that does not exist, a property that is not there or a binding that
 * fails shows up here instead of on the user's settings page. What it
 * decides for a window is asserted by tst_window_mode.qml; this file
 * asserts that the list it shows is the list the config holds.
 */
TestCase {
    id: testCase
    name: "AppWindowRules"
    when: true

    // The list is an item that lives in the settings page, so it is
    // created below a host item.
    Component {
        id: hostFactory
        Item { width: 700; height: 600 }
    }

    Component {
        id: rulesFactory
        AppWindowRules {}
    }

    property var hostInstance: null
    property var rulesInstance: null

    function init() {
        testCase.hostInstance = hostFactory.createObject(null);
        testCase.rulesInstance = rulesFactory.createObject(testCase.hostInstance);
        verify(testCase.rulesInstance !== null, "the rule list could not be created");
    }

    function cleanup() {
        if (testCase.rulesInstance !== null) {
            testCase.rulesInstance.destroy();
            testCase.rulesInstance = null;
        }
        if (testCase.hostInstance !== null) {
            testCase.hostInstance.destroy();
            testCase.hostInstance = null;
        }
    }

    function test_the_list_it_shows_is_the_list_the_config_holds() {
        // The model is loaded from the config on construction, so the two
        // snapshots agree whatever the config of the user holds.
        compare(JSON.stringify(testCase.rulesInstance.snapshot()),
                JSON.stringify(testCase.rulesInstance.configSnapshot()));
    }

    function test_a_rule_without_a_class_is_kept_as_an_empty_string() {
        const shown = testCase.rulesInstance.configSnapshot();
        for (const rule of shown) {
            compare(typeof rule.class, "string");
            verify(rule.mode === "stacking" || rule.mode === "tiling");
        }
    }

    function test_the_running_window_list_offers_a_name_and_a_class() {
        const apps = testCase.rulesInstance.runningApps;
        verify(Array.isArray(apps));
        for (const app of apps) {
            compare(typeof app.displayName, "string");
            compare(typeof app.value, "string");
            verify(app.value.length > 0);
        }
    }
}
