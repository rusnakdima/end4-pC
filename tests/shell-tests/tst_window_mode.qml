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
    // span: a rule that stretches one app over every monitor
    // ------------------------------------------------------------------

    function monitor(x, y, width, height) {
        return { "x": x, "y": y, "width": width, "height": height };
    }

    function test_a_span_rule_floats_in_both_modes() {
        const rules = [{ "class": "^org\\.remmina\\.", "mode": "span" }];
        compare(WindowMode.desiredFloat("org.remmina.Remmina", "tiling", rules), true);
        compare(WindowMode.desiredFloat("org.remmina.Remmina", "stacking", rules), true);
        compare(WindowMode.desiredSpan("org.remmina.Remmina", rules), true);
        compare(WindowMode.desiredSpan("kitty", rules), false);
        compare(WindowMode.desiredSpan("org.remmina.Remmina", []), false);
    }

    function test_the_span_rect_is_the_box_around_every_screen() {
        const rect = WindowMode.spanRectFor([monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)]);
        compare(rect.x, 0);
        compare(rect.y, 0);
        compare(rect.width, 3840);
        compare(rect.height, 1200);
    }

    function test_the_span_rect_handles_a_screen_left_of_the_primary_one() {
        const rect = WindowMode.spanRectFor([monitor(-1920, 0, 1920, 1080), monitor(0, 0, 1920, 1080)]);
        compare(rect.x, -1920);
        compare(rect.y, 0);
        compare(rect.width, 3840);
        compare(rect.height, 1080);
    }

    function test_the_span_rect_handles_stacked_screens_and_gaps() {
        const stacked = WindowMode.spanRectFor([monitor(0, 0, 1920, 1080), monitor(0, 1080, 1920, 1080)]);
        compare(stacked.x, 0);
        compare(stacked.y, 0);
        compare(stacked.width, 1920);
        compare(stacked.height, 2160);

        // A gap in the layout is part of the box: one window cannot skip it.
        const gapped = WindowMode.spanRectFor([monitor(0, 0, 1920, 1080), monitor(2000, 0, 1920, 1080)]);
        compare(gapped.width, 3920);
    }

    function test_the_span_rect_is_rounded_to_whole_layout_pixels() {
        const rect = WindowMode.spanRectFor([monitor(0, 0, 1920.4, 1080.6)]);
        compare(rect.width, 1920);
        compare(rect.height, 1081);
    }

    function test_the_span_rect_survives_empty_or_invalid_screens() {
        compare(WindowMode.spanRectFor([]), null);
        compare(WindowMode.spanRectFor(null), null);
        compare(WindowMode.spanRectFor([null, monitor(0, 0, 0, 1080)]), null);
        const rect = WindowMode.spanRectFor([null, monitor(0, 0, 1920, 1080)]);
        compare(rect.width, 1920);
    }

    function test_rect_matches_allows_a_pixel_of_rounding() {
        const rect = { "x": 0, "y": 0, "width": 3840, "height": 1200 };
        verify(WindowMode.rectMatches({ "at": [0, 0], "size": [3840, 1200] }, rect));
        verify(WindowMode.rectMatches({ "at": [1, 1], "size": [3838, 1198] }, rect));
        verify(!WindowMode.rectMatches({ "at": [100, 0], "size": [3840, 1200] }, rect));
        verify(!WindowMode.rectMatches({ "at": [0, 0], "size": [1920, 1080] }, rect));
    }

    function test_the_default_float_rect_is_a_sane_size_on_the_window_screen() {
        const screens = [monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)];
        // The centre of the window is on the right screen.
        const rect = WindowMode.defaultFloatRect({ "at": [2500, 100], "size": [1000, 600] }, screens);
        compare(rect.width, 1152);
        compare(rect.height, 702);
        verify(rect.x >= 1920);
        verify(rect.x + rect.width <= 3840);
        compare(WindowMode.defaultFloatRect({ "at": [0, 0], "size": [100, 100] }, []), null);
    }

    function test_the_default_float_rect_prefers_the_window_monitor() {
        const screens = [monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)];
        // A span window covers the whole layout, so its centre is no help;
        // the compositor's monitor id says where it belongs.
        const rect = WindowMode.defaultFloatRect({
            "monitor": 0, "at": [0, 0], "size": [3840, 1200]
        }, screens);
        compare(rect.width, 1152);
        compare(rect.height, 780);
        verify(rect.x < 1920);
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

    function test_a_span_rule_floats_sizes_and_suppresses_fullscreen() {
        const rect = { "x": 0, "y": 0, "width": 3840, "height": 1200 };
        const source = WindowMode.rulesSource("tiling", [{ "class": "remmina", "mode": "span" }], rect);
        verify(source.indexOf("float = true") !== -1);
        verify(source.indexOf("size = { 3840, 1200 }") !== -1);
        verify(source.indexOf("border_size = 0") !== -1);
        verify(source.indexOf("rounding = 0") !== -1);
        verify(source.indexOf('opacity = "1 1"') !== -1);
        verify(source.indexOf('suppress_event = "fullscreen"') !== -1);
        // The position comes from the dispatcher; the rule's "move" is not
        // reliable for a window larger than one monitor.
        verify(source.indexOf("move =") === -1);
    }

    function test_a_span_rule_without_a_known_layout_only_floats() {
        const source = WindowMode.rulesSource("tiling", [{ "class": "remmina", "mode": "span" }], null);
        verify(source.indexOf("float = true") !== -1);
        verify(source.indexOf("size = {") === -1);
        verify(source.indexOf("remmina") !== -1);
    }

    function test_the_span_rule_comes_after_the_global_float_rule() {
        const rect = { "x": 0, "y": 0, "width": 3840, "height": 1200 };
        const source = WindowMode.rulesSource("stacking", [{ "class": "remmina", "mode": "span" }], rect);
        const globalFloat = source.indexOf('class = ".*"');
        const spanRule = source.indexOf("remmina");
        verify(globalFloat !== -1);
        verify(spanRule > globalFloat);
        // The global rule plus the span rule; the span entry is not also
        // written as a plain stacking rule.
        compare(source.match(/float = true/g).length, 2);
        verify(source.indexOf("tile = true") === -1);
    }

    function test_the_span_class_pattern_is_escaped_like_any_other() {
        const source = WindowMode.rulesSource("tiling", [{ "class": 'a"b', "mode": "span" }], null);
        verify(source.indexOf('class = "a\\"b"') !== -1);
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

    // ------------------------------------------------------------------
    // reconcilePlan: span
    // ------------------------------------------------------------------

    function spanClient(address, winClass, floating, at, size) {
        return {
            "address": address,
            "class": winClass,
            "floating": floating,
            "at": at ?? [0, 0],
            "size": size ?? [1920, 1080]
        };
    }

    function test_a_tiled_span_window_is_floated_and_stretched() {
        const screens = [monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)];
        const plan = WindowMode.reconcilePlan(
            [spanClient("0x1", "remmina", false)],
            "tiling", [{ "class": "remmina", "mode": "span" }], [], screens, []);

        // Float first, then the geometry: a tiled window does not take a
        // floating rect.
        compare(plan.actions.length, 2);
        compare(plan.actions[0].floating, true);
        compare(plan.actions[1].rect.width, 3840);
        compare(plan.actions[1].rect.height, 1200);
        compare(plan.owned.join(","), "0x1");
        compare(plan.spans.join(","), "0x1");
    }

    function test_a_span_window_that_already_covers_the_layout_gets_no_action() {
        const screens = [monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)];
        const plan = WindowMode.reconcilePlan(
            [spanClient("0x1", "remmina", true, [0, 0], [3840, 1200])],
            "tiling", [{ "class": "remmina", "mode": "span" }], [], screens, []);

        compare(plan.actions.length, 0);
        compare(plan.spans.join(","), "0x1");
    }

    function test_a_span_window_that_the_app_resized_is_stretched_back() {
        const screens = [monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)];
        const plan = WindowMode.reconcilePlan(
            [spanClient("0x1", "remmina", true, [100, 100], [800, 600])],
            "tiling", [{ "class": "remmina", "mode": "span" }], [], screens, []);

        compare(plan.actions.length, 1);
        compare(plan.actions[0].rect.x, 0);
        compare(plan.actions[0].rect.y, 0);
        compare(plan.actions[0].rect.width, 3840);
    }

    function test_a_fullscreen_span_window_is_left_alone() {
        // The span rule suppresses the app's own fullscreen request, but a
        // keybind can still fullscreen it; the service must not fight that
        // by resizing it back on every tick.
        const screens = [monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)];
        const win = spanClient("0x1", "remmina", true, [0, 0], [1920, 1080]);
        win.fullscreen = 1;
        const plan = WindowMode.reconcilePlan(
            [win], "tiling", [{ "class": "remmina", "mode": "span" }], [], screens, []);

        compare(plan.actions.length, 0);
        compare(plan.spans.join(","), "0x1");
    }

    function test_a_window_that_leaves_span_gets_a_sane_size_back() {
        // It floats because of its own rule, so it is not tiled back; only
        // the whole-layout geometry is undone.
        const screens = [monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)];
        const plan = WindowMode.reconcilePlan(
            [spanClient("0x1", "remmina", true, [0, 0], [3840, 1200])],
            "tiling", [], [], screens, ["0x1"]);

        compare(plan.actions.length, 1);
        compare(plan.actions[0].floating, undefined);
        compare(plan.actions[0].rect.width, 1152);
        compare(plan.actions[0].rect.height, 702);
        compare(plan.spans.length, 0);
    }

    function test_a_window_the_service_floated_for_span_is_tiled_back() {
        const screens = [monitor(0, 0, 1920, 1200), monitor(1920, 0, 1920, 1080)];
        const plan = WindowMode.reconcilePlan(
            [spanClient("0x1", "remmina", true, [0, 0], [3840, 1200])],
            "tiling", [], ["0x1"], screens, ["0x1"]);

        // Unfloating tiles it, so a restore rect would be pointless.
        compare(plan.actions.length, 1);
        compare(plan.actions[0].floating, false);
        compare(plan.owned.length, 0);
        compare(plan.spans.length, 0);
    }

    function test_the_closed_span_windows_are_dropped_from_the_span_list() {
        const screens = [monitor(0, 0, 1920, 1200)];
        const plan = WindowMode.reconcilePlan(
            [spanClient("0x1", "remmina", true, [0, 0], [1920, 1200])],
            "tiling", [{ "class": "remmina", "mode": "span" }], [], screens,
            ["0x1", "0xdead"]);

        // 0xdead is gone; 0x1 is still a span window and stays.
        compare(plan.spans.join(","), "0x1");
    }
}
