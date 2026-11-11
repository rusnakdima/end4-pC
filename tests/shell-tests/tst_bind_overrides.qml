import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services

/**
 * The rebind path of the settings panel: setOverride has to leave the
 * combination in the file the Hyprland config reads, otherwise the theme's
 * original key keeps working and the new one never binds.
 *
 * The write goes through a mkdir first and then an asynchronous FileView
 * save, so the test waits for the chain instead of assuming the call is
 * synchronous. The file is removed afterwards, which keeps the next run
 * from passing on a file a previous run left behind.
 */
TestCase {
    id: testCase
    name: "BindOverrides"
    when: true

    property var reader: null

    function cleanup() {
        if (testCase.reader !== null) {
            testCase.reader.destroy();
            testCase.reader = null;
        }
        // Leave no test action behind: clear the map, then drop the file.
        HyprlandBindOverrides.clearOverride("zzTestOnlyAction");
        Quickshell.execDetached(["rm", "-f", HyprlandBindOverrides.overridesPath]);
    }

    function test_set_override_reaches_the_file() {
        HyprlandBindOverrides.setOverride("zzTestOnlyAction", "SUPER + F12");

        // mkdir exits before the file is written.
        tryCompare(HyprlandBindOverrides, "pendingWrite", false, 5000);
        verify(HyprlandBindOverrides.wrote, "the write chain never ran");

        testCase.reader = Qt.createQmlObject(
            "import Quickshell; import Quickshell.Io; FileView { preload: true }",
            testCase, "reader");
        testCase.reader.path = HyprlandBindOverrides.overridesPath;

        tryVerify(() => {
            try {
                return testCase.reader.text().indexOf("zzTestOnlyAction = SUPER + F12") !== -1;
            } catch (e) {
                return false;
            }
        }, 5000, "the override never reached " + HyprlandBindOverrides.overridesPath);
    }

    function test_the_map_offers_the_override_back() {
        HyprlandBindOverrides.setOverride("zzTestOnlyAction", "SUPER + F12");
        compare(HyprlandBindOverrides.comboFor("zzTestOnlyAction", ""), "SUPER + F12");
        verify(HyprlandBindOverrides.isOverridden("zzTestOnlyAction"));
        HyprlandBindOverrides.clearOverride("zzTestOnlyAction");
        compare(HyprlandBindOverrides.comboFor("zzTestOnlyAction", "fallback"), "fallback");
        verify(!HyprlandBindOverrides.isOverridden("zzTestOnlyAction"));
    }
}
