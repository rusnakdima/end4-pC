import QtQuick
import QtTest
import "modules/common/functions/KeybindCommands.js" as Commands

/**
 * Command keybinds are the binds whose dispatch runs a saved command. The
 * settings panel lists them separately and can delete them; built-in commands
 * stay available in the picker, so a delete only disables their bind.
 */
TestCase {
    id: testCase
    name: "KeybindCommands"
    when: true

    function test_command_entries_only_include_commands_with_descriptions() {
        const binds = [
            { id: "custom-1", combo: "SUPER + J", description: "Media: Next", dispatch: { kind: "command", command: "playerctl next" } },
            { id: "plain-1", combo: "SUPER + K", description: "Plain", dispatch: { kind: "command" } },
            { id: "shell-1", combo: "SUPER + U", description: "Shell: Reload theme", dispatch: { kind: "global", arg: { value: "quickshell:shellReload" } } }
        ];
        const entries = Commands.commandEntries(binds);
        compare(entries.length, 1);
        compare(entries[0].category, "Media");
        compare(entries[0].label, "Next");
        compare(entries[0].command, "playerctl next");
    }

    function test_delete_plan_for_overlay_add() {
        const bind = { id: "custom-1", combo: "SUPER + J", description: "Media: Next", dispatch: { kind: "command", command: "playerctl next" } };
        const plan = Commands.deletePlan(bind, () => ({ id: "custom-1" }));
        compare(plan.kind, "add");
        compare(plan.id, "custom-1");
    }

    function test_delete_plan_for_builtin_command() {
        const bind = { id: "bind-27", sourcePath: "main", line: 70, combo: "SUPER + M", description: "Shell: Open mixer", dispatch: { kind: "command", command: "pavucontrol" } };
        const plan = Commands.deletePlan(bind, () => null);
        compare(plan.kind, "builtin");
        compare(plan.id, "bind-27");
        compare(plan.label, "Shell: Open mixer");
        compare(plan.binds.length, 1);
        compare(plan.binds[0].id, "bind-27");
    }
}
