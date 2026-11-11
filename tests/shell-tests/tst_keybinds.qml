import QtQuick
import QtTest
import qs.services

/**
 * The keybind list of the settings panel: how a combination is formatted
 * and which other binds a row has to warn about.
 *
 * The warning rule is "two holders of one key": the theme's keybind file
 * and the user's custom one are both counted, shell shortcuts and the
 * compositor's own binds alike, because every matching bind dispatches on
 * one press. The service reads the live keybind files, so the tests install
 * their own tree and put the real one back afterwards.
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

    function test_repeat_users_never_lists_the_row_itself() {
        const users = HyprlandKeybinds.repeatUsers("SUPER + F6", "actionOne");
        compare(users.length, 1);
        compare(users[0].label, "Second");
        compare(users[0].file, "main");
        // A combination nobody holds warns about nothing.
        compare(HyprlandKeybinds.repeatUsers("SUPER + F8", "actionOne").length, 0);
        compare(HyprlandKeybinds.repeatUsers("", "actionOne").length, 0);
    }

    function test_repeat_users_reports_a_key_two_shortcuts_share() {
        const users = HyprlandKeybinds.repeatUsers("SUPER + F6", "actionTwo");
        compare(users.length, 1);
        compare(users[0].label, "First");
        // The row on the shifted combination sees only the keys it shares.
        compare(HyprlandKeybinds.repeatUsers("SUPER + SHIFT + F6", "actionThree").length, 0);
        compare(HyprlandKeybinds.repeatUsers("SUPER + F6", "actionThree").length, 2);
    }

    function test_a_plain_bind_and_a_shortcut_on_one_key_see_each_other() {
        // F7 is held by a plain bind: a shortcut row on that key must see
        // it, and the plain bind's own row must not list itself. Its id is
        // "file\0bind_<key>", the same the settings rows build.
        const plainId = "main\u0000bind_" + "SUPER + F7".replace(/[^A-Za-z0-9_]/g, "_");
        const holders = HyprlandKeybinds.repeatUsers("SUPER + F7", "");
        compare(holders.length, 1);
        compare(holders[0].label, "Plain");
        compare(holders[0].file, "main");
        compare(HyprlandKeybinds.repeatUsers("SUPER + F7", plainId).length, 0);
        compare(HyprlandKeybinds.repeatUsers("SUPER + F9", plainId).length, 0);
    }

    function test_a_twin_in_the_custom_file_is_a_repeat() {
        // The same combination written in custom/keybinds.lua is the case
        // the user cares about: it must show up for the main-file holder,
        // with a marker saying where the other bind lives.
        HyprlandKeybinds.userKeybinds = {
            "name": "", "children": [], "keybinds": [
                { "mods": ["SUPER"], "key": "F7", "dispatcher": "hl.dsp.exec_cmd", "params": "", "comment": "Custom twin", "action": "" }
            ]
        };
        const plainId = "main\u0000bind_" + "SUPER + F7".replace(/[^A-Za-z0-9_]/g, "_");
        const customId = "custom\u0000bind_" + "SUPER + F7".replace(/[^A-Za-z0-9_]/g, "_");

        const forMain = HyprlandKeybinds.repeatUsers("SUPER + F7", plainId);
        compare(forMain.length, 1);
        compare(forMain[0].label, "Custom twin");
        compare(forMain[0].file, "custom");

        const forCustom = HyprlandKeybinds.repeatUsers("SUPER + F7", customId);
        compare(forCustom.length, 1);
        compare(forCustom[0].label, "Plain");
        compare(forCustom[0].file, "main");
    }

    function test_a_plain_bind_is_not_a_shell_action() {
        const actions = HyprlandKeybinds.shellActions.map(entry => entry.action);
        verify(actions.includes("actionOne"));
        verify(actions.includes("actionTwo"));
        verify(!actions.includes(""));
    }
}
