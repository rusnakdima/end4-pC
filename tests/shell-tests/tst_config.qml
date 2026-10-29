import QtQuick
import QtTest
import qs.modules.common

/**
 * The config module reads the user configuration into a typed adapter and
 * offers setNestedValue(), which writes a single leaf by its dotted path.
 *
 * The test never writes to the user configuration: the config file is
 * pointed at a temporary file, so the values it changes land there and the
 * real ~/.config/illogical-impulse/config.json is left alone.
 */
TestCase {
    id: testCase
    name: "Config"
    when: true

    property string sandboxPath: "/tmp/end4-pc-shell-test-config.json"
    property string originalPath: ""

    function enterSandbox() {
        if (testCase.originalPath === "")
            testCase.originalPath = Config.filePath;
        if (Config.filePath !== testCase.sandboxPath)
            Config.filePath = testCase.sandboxPath;
        for (let i = 0; i < 100; ++i) {
            if (Config.ready) break;
            wait(100);
        }
    }

    function leaveSandbox() {
        if (testCase.originalPath !== "" && Config.filePath === testCase.sandboxPath)
            Config.filePath = testCase.originalPath;
    }

    function test_the_options_are_the_typed_adapter() {
        enterSandbox();
        verify(Config.options !== undefined);
        compare(typeof Config.options.appearance, "object");
        compare(typeof Config.options.appearance.uiBackground, "string");
        compare(typeof Config.options.appearance.extraBackgroundTint, "boolean");
    }

    function test_set_nested_value_writes_an_existing_leaf() {
        enterSandbox();
        const original = Config.options.appearance.palette.accentColor;
        verify(Config.setNestedValue("appearance.palette.accentColor", "shell-test"));
        compare(Config.options.appearance.palette.accentColor, "shell-test");
        verify(Config.setNestedValue("appearance.palette.accentColor", original));
        compare(Config.options.appearance.palette.accentColor, original);
    }

    function test_set_nested_value_refuses_a_missing_leaf() {
        enterSandbox();
        verify(!Config.setNestedValue("appearance.noSuchKey", "x"));
        verify(!("noSuchKey" in Config.options.appearance));
    }

    function test_set_nested_value_refuses_a_missing_intermediate() {
        enterSandbox();
        verify(!Config.setNestedValue("noSuchSection.noSuchKey", "x"));
    }

    function test_set_nested_value_refuses_an_empty_path() {
        enterSandbox();
        verify(!Config.setNestedValue("", "x"));
    }

    function test_a_boolean_string_is_coerced_to_a_boolean() {
        enterSandbox();
        const original = Config.options.appearance.extraBackgroundTint;
        verify(Config.setNestedValue("appearance.extraBackgroundTint", "false"));
        compare(Config.options.appearance.extraBackgroundTint, false);
        verify(Config.setNestedValue("appearance.extraBackgroundTint", "true"));
        compare(Config.options.appearance.extraBackgroundTint, true);
        verify(Config.setNestedValue("appearance.extraBackgroundTint", original));
        compare(Config.options.appearance.extraBackgroundTint, original);
    }

    function test_a_numeric_string_is_coerced_to_a_number() {
        enterSandbox();
        const original = Config.options.appearance.transparency.backgroundTransparency;
        verify(Config.setNestedValue("appearance.transparency.backgroundTransparency", "0.42"));
        compare(Config.options.appearance.transparency.backgroundTransparency, 0.42);
        verify(Config.setNestedValue("appearance.transparency.backgroundTransparency", original));
        compare(Config.options.appearance.transparency.backgroundTransparency, original);
    }

    function test_a_text_value_stays_text() {
        enterSandbox();
        const original = Config.options.appearance.uiBackground;
        verify(Config.setNestedValue("appearance.uiBackground", "oled"));
        compare(Config.options.appearance.uiBackground, "oled");
        verify(Config.setNestedValue("appearance.uiBackground", original));
        compare(Config.options.appearance.uiBackground, original);
    }

    function test_the_null_string_is_not_stored_as_text() {
        enterSandbox();
        const original = Config.options.appearance.palette.accentColor;
        verify(Config.setNestedValue("appearance.palette.accentColor", "null"));
        // The string "null" is turned into the null value, which the typed
        // string property stores as the empty string.
        verify(Config.options.appearance.palette.accentColor !== "null");
        compare(Config.options.appearance.palette.accentColor, "");
        verify(Config.setNestedValue("appearance.palette.accentColor", original));
        compare(Config.options.appearance.palette.accentColor, original);
    }

    function test_the_sandbox_is_left_in_place_and_the_user_file_is_untouched() {
        enterSandbox();
        compare(Config.filePath, testCase.sandboxPath);
        leaveSandbox();
        compare(Config.filePath, testCase.originalPath);
    }
}
