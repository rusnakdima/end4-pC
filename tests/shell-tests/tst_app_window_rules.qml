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
            verify(["stacking", "tiling", "span"].includes(rule.mode));
        }
    }

    function test_every_known_mode_survives_the_snapshot() {
        // A span rule must not be rewritten to stacking by the next edit,
        // and an unknown value still falls back to the safe mode.
        compare(testCase.rulesInstance.normalizeMode("stacking"), "stacking");
        compare(testCase.rulesInstance.normalizeMode("tiling"), "tiling");
        compare(testCase.rulesInstance.normalizeMode("span"), "span");
        compare(testCase.rulesInstance.normalizeMode("nonsense"), "stacking");
        compare(testCase.rulesInstance.normalizeMode(undefined), "stacking");
        verify(testCase.rulesInstance.modeLabel("span") !== testCase.rulesInstance.modeLabel("stacking"));
    }

    function test_a_typed_subclass_is_kept_in_the_model() {
        // Regression: the title field used to write a role that does not
        // exist ("title" instead of "winTitle"), so a subclass like
        // Picture-in-Picture was dropped on the floor and the rule
        // silently widened to every window of the app.
        const rules = testCase.rulesInstance;
        rules.addEntry();
        const index = rules.snapshot().length - 1;
        try {
            rules.setField(index, "winClass", "zen");
            rules.setField(index, "winTitle", "Picture-in-Picture");
            const entry = rules.snapshot()[index];
            compare(entry.class, "zen");
            compare(entry.title, "Picture-in-Picture");
            compare(entry.disableOpacity, false);

            // The subclass survives a round trip through the config view
            // as well: that is what the settings page reads back.
            const fromConfig = rules.configSnapshot()[index];
            compare(fromConfig.title, "Picture-in-Picture");
        } finally {
            rules.removeEntry(index);
        }
        compare(JSON.stringify(rules.snapshot()), JSON.stringify(rules.configSnapshot()));
    }

    function test_the_running_window_list_offers_a_name_class_and_title() {
        const windows = testCase.rulesInstance.runningWindows;
        verify(Array.isArray(windows));
        for (const win of windows) {
            compare(typeof win.displayName, "string");
            compare(typeof win.value, "string");
            verify(win.value.length > 0);
            compare(typeof win.winClass, "string");
            verify(win.winClass.length > 0);
            compare(typeof win.winTitle, "string");
        }
        // Every app that is running is offered as a whole, plus each of
        // its windows with a title for targeting a single one.
        const wholeApps = windows.filter(win => win.winTitle === "");
        for (const app of wholeApps) {
            verify(windows.some(win => win.winClass === app.winClass && win.winTitle !== ""));
        }
    }

    function test_the_picker_shows_the_entry_the_rule_describes() {
        const rules = testCase.rulesInstance;
        // Nothing selected without a class, and the placeholder is what a
        // typed subclass that is not running falls back to.
        compare(rules.currentPickerValue("", ""), "");
        compare(rules.currentPickerValue("definitely-not-running", "whatever"), "");
    }
}
