import QtQuick
import QtTest
import "KeyCombos.js" as KeyCombos

/**
 * Tests for the key combination helper.
 *
 * The settings panel turns a key press into a Hyprland key combination and
 * writes it to the override file, so the spelling of the modifiers and of the
 * key names has to be the one Hyprland understands.
 */
TestCase {
    id: testCase
    name: "KeyCombos"
    when: windowShown

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

    function test_display_label_reads_like_words() {
        compare(KeyCombos.displayLabel("SUPER"), "Super");
        compare(KeyCombos.displayLabel("CTRL"), "Ctrl");
        compare(KeyCombos.displayLabel("SHIFT"), "Shift");
        compare(KeyCombos.displayLabel("ALT"), "Alt");
        compare(KeyCombos.displayLabel("Return"), "Enter");
        compare(KeyCombos.displayLabel("Escape"), "Esc");
        compare(KeyCombos.displayLabel("BackSpace"), "Backspace");
        compare(KeyCombos.displayLabel("space"), "Space");
        compare(KeyCombos.displayLabel("Page_Up"), "Page Up");
    }

    function test_display_label_shows_punctuation_as_the_character() {
        compare(KeyCombos.displayLabel("Slash"), "/");
        compare(KeyCombos.displayLabel("Period"), ".");
        compare(KeyCombos.displayLabel("Comma"), ",");
        compare(KeyCombos.displayLabel("BracketLeft"), "[");
        // A backslash must survive as one character.
        compare(KeyCombos.displayLabel("Backslash"), "\\");
    }

    function test_display_label_keeps_unknown_tokens() {
        // Media keys, mouse buttons and function keys are not remapped.
        compare(KeyCombos.displayLabel("XF86AudioPlay"), "XF86AudioPlay");
        compare(KeyCombos.displayLabel("mouse:274"), "mouse:274");
        compare(KeyCombos.displayLabel("F5"), "F5");
        compare(KeyCombos.displayLabel("K"), "K");
        compare(KeyCombos.displayLabel(""), "");
        compare(KeyCombos.displayLabel(undefined), "");
        compare(KeyCombos.displayLabel(null), "");
    }

    function test_display_parts_splits_a_combo() {
        compare(KeyCombos.displayParts("CTRL + SUPER + K").join("|"), "Ctrl|Super|K");
        compare(KeyCombos.displayParts("SUPER + Return").join("|"), "Super|Enter");
        compare(KeyCombos.displayParts("").length, 0);
        compare(KeyCombos.displayParts(undefined).length, 0);
    }

    function test_combo_from_text_accepts_any_spelling() {
        compare(KeyCombos.comboFromText("super+i"), "SUPER + I");
        compare(KeyCombos.comboFromText("Super + I"), "SUPER + I");
        compare(KeyCombos.comboFromText("i super"), "SUPER + I");
        compare(KeyCombos.comboFromText("ctrl shift k"), "CTRL + SHIFT + K");
        compare(KeyCombos.comboFromText(""), "");
        compare(KeyCombos.comboFromText("shift"), "");
    }

    function test_canonical_combo_ignores_order_case_and_separators() {
        compare(KeyCombos.canonicalCombo("SUPER + I"), "super+i");
        compare(KeyCombos.canonicalCombo("i + super"), "super+i");
        verify(KeyCombos.comboMatches("super i", "SUPER + I"));
        verify(!KeyCombos.comboMatches("super o", "SUPER + I"));
    }
}
