import QtQuick
import QtTest
import qs.services

/**
 * The keybind list of the settings panel: how a combination is formatted
 * and which other shortcuts a row has to warn about.
 *
 * The warning rule is shell-shortcut to shell-shortcut only: the theme
 * deliberately repeats a shortcut's key as a fallback bind (it runs when
 * the shell is dead), and warning about those would point at the feature
 * the row already describes. The service reads the live keybind files, so
 * the tests install their own tree and put the real one back afterwards.
 */
TestCase {
    id: testCase
    name: "Keybinds"
    when: true

    property var savedDefault: null
    property var savedUser: null

    function init() {
        testCase.savedDefault = HyprlandKeybinds.defaultKeybinds;
        testCase.savedUser = HyprlandKeybinds.userKeybinds;
        HyprlandKeybinds.defaultKeybinds = {
            "name": "", "children": [], "keybinds": [
                { "mods": ["SUPER"], "key": "F6", "dispatcher": "hl.dsp.global", "params": "", "comment": "First", "action": "actionOne" },
                { "mods": ["SUPER"], "key": "F6", "dispatcher": "hl.dsp.global", "params": "", "comment": "Second", "action": "actionTwo" },
                { "mods": ["SUPER", "SHIFT"], "key": "F6", "dispatcher": "hl.dsp.global", "params": "", "comment": "Third", "action": "actionThree" },
                { "mods": ["SUPER"], "key": "F7", "dispatcher": "hl.dsp.exec_cmd", "params": "", "comment": "Plain", "action": "" }
            ]
        };
        HyprlandKeybinds.userKeybinds = { "name": "", "children": [], "keybinds": [] };
    }

    function cleanup() {
        HyprlandKeybinds.defaultKeybinds = testCase.savedDefault;
        HyprlandKeybinds.userKeybinds = testCase.savedUser;
    }

    function test_combo_joins_the_modifiers_and_the_key() {
        compare(HyprlandKeybinds.comboOf({ "mods": ["CTRL", "SUPER"], "key": "Space" }), "CTRL + SUPER + Space");
        compare(HyprlandKeybinds.comboOf({ "mods": [], "key": "mouse:274" }), "mouse:274");
    }

    function test_combo_users_never_lists_the_row_itself() {
        const users = HyprlandKeybinds.comboUsers("SUPER + F6", "actionOne");
        compare(users.length, 1);
        compare(users[0].action, "actionTwo");
        compare(users[0].label, "Second");
        // A combination no shortcut holds warns about nothing.
        compare(HyprlandKeybinds.comboUsers("SUPER + F8", "actionOne").length, 0);
    }

    function test_combo_users_reports_a_key_two_shortcuts_share() {
        const users = HyprlandKeybinds.comboUsers("SUPER + F6", "actionTwo");
        compare(users.length, 1);
        compare(users[0].action, "actionOne");
        compare(users[0].label, "First");
        // The row on the shifted combination sees both keys it does not hold
        // as separate: only the ones it shares count.
        const shifted = HyprlandKeybinds.comboUsers("SUPER + SHIFT + F6", "actionThree");
        compare(shifted.length, 0);
        compare(HyprlandKeybinds.comboUsers("SUPER + F6", "actionThree").length, 2);
    }

    function test_combo_users_ignores_the_compositors_own_binds() {
        // F7 is held by a plain bind only; a shell shortcut row must not
        // warn about it, and an unshared or empty key warns about nothing.
        compare(HyprlandKeybinds.comboUsers("SUPER + F7", "").length, 0);
        compare(HyprlandKeybinds.comboUsers("SUPER + F9", "").length, 0);
        compare(HyprlandKeybinds.comboUsers("", "").length, 0);
    }

    function test_a_plain_bind_is_not_a_shell_action() {
        const actions = HyprlandKeybinds.shellActions.map(entry => entry.action);
        verify(actions.includes("actionOne"));
        verify(actions.includes("actionTwo"));
        verify(!actions.includes(""));
    }
}
