import QtQuick
import QtTest
import qs.services

/**
 * The window mode decides which windows float: the stacking mode floats
 * every window so they overlap, the tiling mode keeps the layout, and an
 * app rule puts one app on the other side of that choice.
 *
 * Everything the service decides lives in pure functions, so this file
 * asserts them with fixtures. Nothing here writes the rules file or
 * dispatches into the running compositor: the service only does that from
 * apply() and reconcile(), which no test calls.
 */
TestCase {
    id: testCase
    name: "WindowMode"
    when: true

    function client(address, winClass, floating) {
        return { "address": address, "class": winClass, "floating": floating };
    }

    // ------------------------------------------------------------------
    // matchRule
    // ------------------------------------------------------------------

    function test_match_rule_returns_the_first_rule_that_matches() {
        // Both patterns find "firefox", so the first one has to win, and
        // "waterfox" is found by the second one alone.
        const rules = [
            { "class": "fire.*", "mode": "stacking" },
            { "class": "fox", "mode": "tiling" },
        ];
        compare(WindowMode.matchRule("firefox", rules).mode, "stacking");
        compare(WindowMode.matchRule("waterfox", rules).mode, "tiling");
        compare(WindowMode.matchRule("kitty", rules), null);
    }

    function test_match_rule_searches_the_pattern_the_way_the_compositor_does() {
        // The compositor searches its class rules instead of anchoring
        // them, so "firefox" has to find "org.mozilla.firefox" here too.
        const rules = [{ "class": "firefox", "mode": "tiling" }];
        verify(WindowMode.matchRule("org.mozilla.firefox", rules) !== null);
    }

    function test_match_rule_survives_an_empty_or_invalid_pattern() {
        const rules = [
            { "class": "", "mode": "tiling" },
            { "class": "[unclosed", "mode": "stacking" },
            { "class": "kitty", "mode": "tiling" },
        ];
        // An invalid pattern matches nothing instead of throwing, and the
        // search carries on with the rules behind it.
        compare(WindowMode.matchRule("kitty", rules).mode, "tiling");
        verify(WindowMode.matchRule("anything", [{ "class": "[unclosed", "mode": "tiling" }]) === null);
        verify(WindowMode.matchRule("kitty", []) === null);
    }

    // ------------------------------------------------------------------
    // desiredFloat
    // ------------------------------------------------------------------

    function test_the_stacking_mode_floats_every_window_without_a_rule() {
        compare(WindowMode.desiredFloat("kitty", "stacking", []), true);
        compare(WindowMode.desiredFloat("org.mozilla.firefox", "stacking", []), true);
    }

    function test_the_stacking_mode_keeps_an_always_tiling_app_on_the_grid() {
        const rules = [{ "class": "^steam$", "mode": "tiling" }];
        compare(WindowMode.desiredFloat("steam", "stacking", rules), false);
        compare(WindowMode.desiredFloat("kitty", "stacking", rules), true);
    }

    function test_the_tiling_mode_only_floats_an_always_stacking_app() {
        const rules = [{ "class": "pavucontrol", "mode": "stacking" }];
        compare(WindowMode.desiredFloat("pavucontrol", "tiling", rules), true);

        // null means the mode has no opinion and the window keeps what it
        // has, so a dialog that floats because of its own rule is never
        // tiled back and a window the user floated stays floating.
        compare(WindowMode.desiredFloat("kitty", "tiling", rules), null);
        compare(WindowMode.desiredFloat("steam", "tiling", [{ "class": "steam", "mode": "tiling" }]), null);
    }

    // ------------------------------------------------------------------
    // rulesSource
    // ------------------------------------------------------------------

    function test_the_tiling_mode_writes_no_global_float_rule() {
        const source = WindowMode.rulesSource("tiling", []);
        verify(source.indexOf("float = true") === -1);
        verify(source.indexOf("Window mode: tiling") !== -1);
    }

    function test_the_stacking_mode_floats_every_window_with_one_rule() {
        const source = WindowMode.rulesSource("stacking", []);
        verify(source.indexOf('class = ".*"') !== -1);
        compare(source.match(/float = true/g).length, 1);
        verify(source.indexOf("tile = true") === -1);
    }

    function test_an_always_tiling_rule_is_written_after_the_global_float_rule() {
        // The shell rules load after hyprland/rules.lua and the last
        // matching rule wins, so the exception has to come last.
        const source = WindowMode.rulesSource("stacking", [{ "class": "^steam$", "mode": "tiling" }]);
        const globalFloat = source.indexOf('class = ".*"');
        const tileRule = source.indexOf("tile = true");
        verify(globalFloat !== -1);
        verify(tileRule > globalFloat);
        verify(source.indexOf('class = "^steam$"') !== -1);
    }

    function test_a_rule_that_only_repeats_the_mode_is_left_out() {
        // In stacking mode an always stacking app floats anyway, and in
        // tiling mode an always tiling app tiles anyway. Leaving those out
        // keeps the file identical across a mode switch that changes
        // nothing but the mode itself.
        verify(WindowMode.rulesSource("stacking", [{ "class": "pavucontrol", "mode": "stacking" }]).indexOf("pavucontrol") === -1);
        verify(WindowMode.rulesSource("tiling", [{ "class": "steam", "mode": "tiling" }]).indexOf("steam") === -1);

        // The rules that do contradict the mode are written.
        verify(WindowMode.rulesSource("tiling", [{ "class": "pavucontrol", "mode": "stacking" }]).indexOf("pavucontrol") !== -1);
        verify(WindowMode.rulesSource("stacking", [{ "class": "steam", "mode": "tiling" }]).indexOf("steam") !== -1);
    }

    function test_a_rule_without_a_class_pattern_is_skipped() {
        const source = WindowMode.rulesSource("tiling", [
            { "class": "", "mode": "stacking" },
            { "class": "pavucontrol", "mode": "stacking" },
        ]);
        compare(source.match(/float = true/g).length, 1);
        verify(source.indexOf("pavucontrol") !== -1);
    }

    function test_the_class_pattern_is_escaped_for_the_lua_string() {
        compare(WindowMode.luaQuote('a"b'), 'a\\"b');
        compare(WindowMode.luaQuote("a\\b"), "a\\\\b");
        compare(WindowMode.luaQuote("a\nb"), "ab");
        compare(WindowMode.luaQuote(""), "");
    }

    // ------------------------------------------------------------------
    // reconcilePlan
    // ------------------------------------------------------------------

    function test_the_stacking_mode_floats_the_windows_that_are_tiled() {
        const plan = WindowMode.reconcilePlan(
            [client("0x1", "kitty", false), client("0x2", "kitty", true)],
            "stacking", [], []);

        compare(plan.actions.length, 1);
        compare(plan.actions[0].address, "0x1");
        compare(plan.actions[0].floating, true);
        // The window that was already floating did not float because of
        // the service, so it does not become its property and a later
        // switch back to tiling leaves it alone.
        compare(plan.owned.join(","), "0x1");
    }

    function test_a_window_the_service_floated_stays_its_property() {
        const plan = WindowMode.reconcilePlan([client("0x1", "kitty", true)], "stacking", [], ["0x1"]);
        compare(plan.actions.length, 0);
        compare(plan.owned.join(","), "0x1");
    }

    function test_the_tiling_mode_tiles_back_only_the_windows_it_floated() {
        const plan = WindowMode.reconcilePlan(
            [client("0x1", "kitty", true), client("0x2", "pavucontrol", true)],
            "tiling", [], ["0x1"]);

        compare(plan.actions.length, 1);
        compare(plan.actions[0].address, "0x1");
        compare(plan.actions[0].floating, false);
        // pavucontrol floats because of its own rule and was never floated
        // by the service, so it keeps floating.
        compare(plan.owned.length, 0);
    }

    function test_an_always_tiling_app_is_taken_off_the_float_in_stacking_mode() {
        const plan = WindowMode.reconcilePlan(
            [client("0x1", "steam", true)],
            "stacking", [{ "class": "steam", "mode": "tiling" }], []);

        compare(plan.actions.length, 1);
        compare(plan.actions[0].floating, false);
        compare(plan.owned.length, 0);
    }

    function test_an_always_stacking_app_is_floated_in_tiling_mode() {
        const plan = WindowMode.reconcilePlan(
            [client("0x1", "pavucontrol", false)],
            "tiling", [{ "class": "pavucontrol", "mode": "stacking" }], []);

        compare(plan.actions.length, 1);
        compare(plan.actions[0].address, "0x1");
        compare(plan.actions[0].floating, true);
        compare(plan.owned.join(","), "0x1");
    }

    function test_the_windows_that_closed_are_dropped_from_the_own_list() {
        // 0xdead is gone and 0x1 is tiled with no rule asking for floating:
        // neither is touched and the list ends up empty.
        const plan = WindowMode.reconcilePlan(
            [client("0x1", "kitty", false)],
            "tiling", [], ["0x1", "0xdead"]);

        compare(plan.actions.length, 0);
        compare(plan.owned.length, 0);
    }
}
