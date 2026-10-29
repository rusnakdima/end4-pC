import QtQuick
import QtTest
import "modules/common/functions/KeyCombos.js" as KeyCombos

/**
 * Tests for the key combination helper.
 *
 * The settings panel turns a key press into a Hyprland key combination and
 * writes it to the override file, so the spelling of the modifiers and of
 * the key names has to be the one Hyprland understands.
 *
 * These are the cases of modules/common/functions/tst_keycombos.qml, which
 * runs them under qmltestrunner. The JavaScript module is imported through
 * the "modules" symlink of this directory, because the file is not part of
 * the "qs" module tree.
 */
TestCase {
    id: testCase
    name: "KeyCombos"
    when: true

    function test_plain_key_has_no_modifier() {
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_V, modifiers: Qt.NoModifier, text: "v" }), "V");
    }

    function test_super_and_alt() {
        compare(
            KeyCombos.keyEventToCombo({
                key: Qt.Key_V,
                modifiers: Qt.MetaModifier | Qt.AltModifier,
                text: "v",
            }),
            "SUPER + ALT + V");
    }

    function test_modifier_order() {
        // The order the theme writes its own binds in.
        compare(
            KeyCombos.keyEventToCombo({
                key: Qt.Key_T,
                modifiers: Qt.MetaModifier | Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier,
                text: "t",
            }),
            "CTRL + SUPER + SHIFT + ALT + T");
    }

    function test_named_keys_use_the_hyprland_spelling() {
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Escape, modifiers: Qt.NoModifier, text: "" }), "Escape");
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Return, modifiers: Qt.NoModifier, text: "" }), "Return");
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Space, modifiers: Qt.NoModifier, text: " " }), "space");
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Period, modifiers: Qt.NoModifier, text: "." }), "Period");
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Slash, modifiers: Qt.NoModifier, text: "/" }), "Slash");
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_F5, modifiers: Qt.NoModifier, text: "" }), "F5");
    }

    function test_unknown_key_falls_back_to_the_text() {
        compare(KeyCombos.keyEventToCombo({ key: 0, modifiers: Qt.NoModifier, text: ";" }), ";");
    }

    function test_modifier_presses_are_ignored() {
        // A modifier on its own is not a combination Hyprland could bind.
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Shift, modifiers: Qt.ShiftModifier, text: "" }), "");
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Control, modifiers: Qt.ControlModifier, text: "" }), "");
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Alt, modifiers: Qt.AltModifier, text: "" }), "");
        compare(KeyCombos.keyEventToCombo({ key: Qt.Key_Meta, modifiers: Qt.MetaModifier, text: "" }), "");
    }

    function test_missing_event_is_ignored() {
        compare(KeyCombos.keyEventToCombo(undefined), "");
        compare(KeyCombos.keyEventToCombo(null), "");
    }
}
