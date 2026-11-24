import QtQuick
import QtTest
import "modules/common/functions/DefaultAppsStore.js" as Store

/**
 * The pure layer behind the Default apps page.
 *
 * Roles are fixed to the frozen catalog's Apps binds: writing an override for
 * one of these ids is what makes the shortcut launch the chosen app. A bind
 * that is outside that set (the settings app, window resize, the YTM custom
 * bind, user binds) must never be claimed by this page, and a terminal pick
 * must reach all three terminal aliases or the other shortcuts keep opening
 * the old emulator.
 *
 * Expectations are spelled out as literals. Nothing here derives an expected
 * value from the store under test.
 */
TestCase {
    id: testCase
    name: "DefaultAppsStore"
    when: true

    function test_known_bind_ids_map_to_the_right_role() {
        const cases = [
            ["apps",    "terminal"],
            ["apps-2",  "terminal"],
            ["apps-3",  "terminal"],
            ["apps-4",  "filemanager"],
            ["apps-5",  "browser"],
            ["apps-6",  "codeeditor"],
            ["apps-7",  "office"],
            ["apps-8",  "texteditor"],
            ["apps-9",  "volumemixer"],
            ["apps-11", "taskmanager"]
        ];
        for (const pair of cases) {
            const role = Store.roleForBindId(pair[0]);
            verify(role !== null, "no role claims " + pair[0]);
            compare(role.id, pair[1], "wrong role for " + pair[0]);
        }
    }

    function test_unrelated_binds_are_not_default_app_roles() {
        const ids = ["apps-10", "apps-12", "apps-13", "main:Terminal", "", null];
        for (const id of ids) {
            compare(Store.roleForBindId(id), null, "unexpected role for " + id);
        }
    }

    function test_command_from_exec_strips_field_codes() {
        compare(Store.commandFromExec("firefox --new-window %U"), "firefox --new-window");
        compare(Store.commandFromExec("kate %f %F"), "kate");
        compare(Store.commandFromExec("kitty -1 fish -c yazi"), "kitty -1 fish -c yazi");
        compare(Store.commandFromExec("100%% of the time %u"), "100% of the time");
    }

    function test_command_from_exec_rejects_an_exec_without_a_command() {
        compare(Store.commandFromExec(""), "");
        compare(Store.commandFromExec("   "), "");
        compare(Store.commandFromExec("%U"), "");
        compare(Store.commandFromExec(null), "");
    }

    function test_bind_ids_belong_to_exactly_one_role() {
        const seen = new Set();
        for (const role of Store.ROLES) {
            for (const id of role.bindIds) {
                verify(!seen.has(id), "duplicate role bind id: " + id);
                seen.add(id);
            }
        }
        compare(seen.size, 10, "the eight roles should cover ten catalog binds");
    }

    function test_matches_command_ignores_field_codes_but_not_arguments() {
        const entry = { execString: "firefox --new-window %U" };
        verify(Store.matchesCommand(entry, "firefox --new-window"), "the chosen app was not recognised");
        verify(!Store.matchesCommand(entry, "firefox"), "a different command must not match");
        verify(!Store.matchesCommand({ execString: "" }, "firefox"), "an empty exec must not match");
    }

    function test_override_command_is_read_from_the_dispatch() {
        const overlay = {
            overrides: {
                "apps-5": { dispatch: { kind: "command", id: "apps-5", command: "zen-browser" } },
                "apps-6": { combo: "SUPER + ALT + C" }
            }
        };
        compare(Store.commandForOverlay(overlay, "apps-5"), "zen-browser");
        compare(Store.commandForOverlay(overlay, "apps-6"), "", "a combo-only override is not an app choice");
        compare(Store.commandForOverlay(overlay, "apps-8"), "", "a bind without an override has no chosen app");
    }

    function test_override_presence_is_reported_for_a_role() {
        const overlay = {
            overrides: {
                "apps": { dispatch: { command: "alacritty" } },
                "apps-4": { enabled: false }
            }
        };
        verify(Store.isOverriddenIn(overlay, "apps"), "the terminal override was missed");
        verify(Store.isOverriddenIn(overlay, "apps-4"), "any override counts, not just a command");
        verify(!Store.isOverriddenIn(overlay, "apps-5"), "an untouched bind must report no override");
        verify(!Store.isOverriddenIn({}, "apps"), "an empty overlay must report no override");
    }
}
