import QtQuick
import QtTest
import qs.services

/**
 * While the Keyboard page is recording a combination, no theme shortcut may
 * stay registered: the pressed chord would otherwise run the action at the
 * same moment it is being captured. The flag is the single gate, and it must
 * restore every shortcut when capture ends or the page is left.
 */
TestCase {
    id: testCase
    name: "KeybindCapture"
    when: true

    function cleanup() {
        GlobalStates.keybindCaptureArmed = false;
    }

    function test_wrapper_is_inactive_while_capturing() {
        const component = Qt.createComponent("services/CompositorGlobalShortcut.qml");
        verify(component.status === Component.Ready,
            "CompositorGlobalShortcut did not load: " + component.errorString());
        const wrapper = component.createObject(testCase);
        verify(wrapper !== null, "CompositorGlobalShortcut could not be created");

        tryCompare(wrapper, "active", true);
        GlobalStates.keybindCaptureArmed = true;
        tryCompare(wrapper, "active", false);
        GlobalStates.keybindCaptureArmed = false;
        tryCompare(wrapper, "active", true);
        wrapper.destroy();
    }

    function test_generated_shortcuts_are_unloaded_while_capturing() {
        // The fixture is read by FileView asynchronously; wait for the 51
        // generated commands to register before checking the capture gate.
        tryCompare(GeneratedCommandShortcuts, "shortcutCount", 51);
        verify(GeneratedCommandShortcuts.activeShortcutIds.length > 0,
            "the generated commands must be registered outside capture");
        GlobalStates.keybindCaptureArmed = true;
        compare(GeneratedCommandShortcuts.activeShortcutIds.length, 0,
            "every generated command shortcut must be unloaded while capturing");
        GlobalStates.keybindCaptureArmed = false;
        verify(GeneratedCommandShortcuts.activeShortcutIds.length > 0,
            "the generated commands must come back after capture");
    }

    function test_cheatsheet_shortcuts_are_disabled_while_capturing() {
        const component = Qt.createComponent("modules/ii/cheatsheet/Cheatsheet.qml");
        verify(component.status === Component.Ready,
            "Cheatsheet did not load: " + component.errorString());
        const cheatsheet = component.createObject(testCase);
        verify(cheatsheet !== null, "Cheatsheet could not be created");

        GlobalStates.keybindCaptureArmed = true;
        verify(!cheatsheet.globalShortcutsEnabled, "cheatsheet shortcuts must be off while capturing");
        GlobalStates.keybindCaptureArmed = false;
        verify(cheatsheet.globalShortcutsEnabled, "cheatsheet shortcuts must come back after capture");
        cheatsheet.destroy();
    }
}
