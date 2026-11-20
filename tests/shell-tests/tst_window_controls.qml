import QtQuick
import QtTest
import qs.services

/**
 * The window-control service decides which dispatcher a button uses and what
 * the current window type is. Every one of those decisions is a pure function
 * in WindowControls.qml, so this file asserts them with fixtures. Nothing
 * here dispatches into the compositor: the impure functions (close, maximize,
 * minimize, setType) are deliberately not called.
 */
TestCase {
    id: testCase
    name: "WindowControls"
    when: true

    function client(address, winClass, options) {
        const base = { "address": address, "class": winClass, "floating": false };
        return Object.assign(base, options ?? {});
    }

    // ------------------------------------------------------------------
    // normalizeAddress / findClient
    // ------------------------------------------------------------------

    function test_normalize_address_accepts_the_shapes_callers_use() {
        compare(WindowControls.normalizeAddress("0xABC123"), "0xabc123");
        compare(WindowControls.normalizeAddress("ABC123"), "0xabc123");
        compare(WindowControls.normalizeAddress("address:0xabc123"), "0xabc123");
        compare(WindowControls.normalizeAddress("0xabc123, kitty"), "0xabc123");
        compare(WindowControls.normalizeAddress("  0xabc123  "), "0xabc123");
        compare(WindowControls.normalizeAddress(""), "");
        compare(WindowControls.normalizeAddress(null), "");
    }

    function test_find_client_uses_the_map_key_and_a_normalized_fallback() {
        const first = client("0x1", "kitty");
        const map = { "0x1": first, "0X2": client("0x2", "zen") };
        compare(WindowControls.findClient(map, "0x1"), first);
        compare(WindowControls.findClient(map, "address:0x1"), first);
        // The map key has a capital X; the fallback scan still finds it.
        compare(WindowControls.findClient(map, "0x2")?.class, "zen");
        compare(WindowControls.findClient(map, "0xdead"), null);
        compare(WindowControls.findClient({}, "0x1"), null);
    }

    // ------------------------------------------------------------------
    // Minimized state
    // ------------------------------------------------------------------

    function test_is_minimized_recognizes_both_hyprland_flags() {
        verify(WindowControls.isMinimized(client("0x1", "kitty", { "hidden": true })));
        verify(WindowControls.isMinimized(client("0x2", "kitty", { "mapped": false })));
        verify(!WindowControls.isMinimized(client("0x3", "kitty", { "hidden": false, "mapped": true })));
        verify(!WindowControls.isMinimized(null));
    }

    function test_can_minimize_and_can_maximize_respect_the_state() {
        const normal = client("0x1", "kitty");
        const hidden = client("0x2", "kitty", { "hidden": true });
        const span = client("0x3", "remmina");
        const spanRules = [{ "class": "remmina", "mode": "span" }];

        verify(WindowControls.canMinimize(normal));
        verify(!WindowControls.canMinimize(hidden));
        verify(WindowControls.canMaximize(normal, []));
        verify(!WindowControls.canMaximize(hidden, []));
        verify(!WindowControls.canMaximize(span, spanRules));
    }

    // ------------------------------------------------------------------
    // Window type
    // ------------------------------------------------------------------

    function test_window_type_prefers_span_then_mode_then_float_flag() {
        const tiling = client("0x1", "kitty");
        const floating = client("0x2", "kitty", { "floating": true });
        const span = client("0x3", "remmina");
        const spanRules = [{ "class": "remmina", "mode": "span" }];

        compare(WindowControls.windowTypeFor(tiling, "tiling", []), "tiling");
        compare(WindowControls.windowTypeFor(floating, "tiling", []), "floating");
        // Stacking is session-wide and wins over the per-window flag.
        compare(WindowControls.windowTypeFor(floating, "stacking", []), "stacking");
        // Span is a per-app rule and wins over both.
        compare(WindowControls.windowTypeFor(span, "tiling", spanRules), "span");
        compare(WindowControls.windowTypeFor(span, "stacking", spanRules), "span");
        compare(WindowControls.windowTypeFor(null, "tiling", []), "tiling");
    }

    function test_cycling_visits_every_type_and_wraps_around() {
        compare(WindowControls.windowTypes.length, 4);
        compare(WindowControls.nextType("floating"), "tiling");
        compare(WindowControls.nextType("tiling"), "stacking");
        compare(WindowControls.nextType("stacking"), "span");
        compare(WindowControls.nextType("span"), "floating");
        compare(WindowControls.nextType("nonsense"), "floating");
    }

    function test_is_window_type_only_accepts_the_known_names() {
        verify(WindowControls.isWindowType("floating"));
        verify(WindowControls.isWindowType("span"));
        verify(!WindowControls.isWindowType("maximize"));
        verify(!WindowControls.isWindowType(""));
    }

    // ------------------------------------------------------------------
    // Span rules
    // ------------------------------------------------------------------

    function test_pattern_matches_class_searches_and_survives_bad_regex() {
        verify(WindowControls.patternMatchesClass("firefox", "org.mozilla.firefox"));
        verify(WindowControls.patternMatchesClass("^steam$", "steam"));
        verify(!WindowControls.patternMatchesClass("^steam$", "steam-webhelper"));
        verify(!WindowControls.patternMatchesClass("[unclosed", "anything"));
        verify(!WindowControls.patternMatchesClass("", "kitty"));
    }

    function test_has_span_rule_does_not_duplicate_an_existing_rule() {
        const rules = [{ "class": "^org\\.remmina\\.", "mode": "span" }];
        verify(WindowControls.hasSpanRule(rules, "org.remmina.Remmina"));
        verify(!WindowControls.hasSpanRule(rules, "kitty"));
        verify(!WindowControls.hasSpanRule([{ "class": "remmina", "mode": "stacking" }], "remmina"));
    }

    // ------------------------------------------------------------------
    // View helpers (shared by the cluster and the type menu)
    // ------------------------------------------------------------------

    function test_shows_button_reads_the_configured_button_list() {
        const buttons = ["minimize", "close", "type"];
        verify(WindowControls.showsButton(buttons, "minimize"));
        verify(WindowControls.showsButton(buttons, "type"));
        verify(!WindowControls.showsButton(buttons, "maximize"));
        verify(!WindowControls.showsButton([], "close"));
        verify(!WindowControls.showsButton(null, "close"));
    }

    function test_window_state_uses_glyphs_that_render_in_this_font() {
        // "maximize"/"restore" render as a dash and a clock in the bundled
        // Material Symbols font; these verified glyphs are used instead.
        compare(WindowControls.windowStateSymbol(0), "crop_square");
        compare(WindowControls.windowStateSymbol(1), "filter_none");
        compare(WindowControls.windowStateSymbol(2), "filter_none");
        compare(WindowControls.windowStateSymbol(null), "crop_square");
    }

    function test_every_type_has_a_symbol_and_a_readable_label() {
        compare(WindowControls.typeSymbol("floating"), "open_in_full");
        compare(WindowControls.typeSymbol("tiling"), "grid_view");
        compare(WindowControls.typeSymbol("stacking"), "layers");
        compare(WindowControls.typeSymbol("span"), "crop_free");
        compare(WindowControls.typeLabel("floating"), "Floating");
        compare(WindowControls.typeLabel("tiling"), "Tiling");
        compare(WindowControls.typeLabel("stacking"), "Stacking");
        compare(WindowControls.typeLabel("span"), "Span (all monitors)");
        // An unknown type still renders something instead of an empty icon.
        compare(WindowControls.typeSymbol("other"), "layers");
        compare(WindowControls.typeLabel("other"), "other");
    }

    // ------------------------------------------------------------------
    // Dispatchers and the fallback chain
    // ------------------------------------------------------------------

    function test_dispatchers_target_the_address_and_use_the_verified_syntax() {
        verify(WindowControls.closeDispatcher("0x1").indexOf('address:0x1') >= 0);
        verify(WindowControls.closeDispatcher("0x1").indexOf('hl.dsp.window.close') === 0);
        verify(WindowControls.focusDispatcher("0x1").indexOf('hl.dsp.focus') === 0);
        // Verified against keybinds.lua: SUPER+D maximizes with this call.
        verify(WindowControls.maximizeDispatcher("0x1", 0).indexOf('hl.dsp.window.fullscreen') === 0);
        verify(WindowControls.maximizeDispatcher("0x1", 0).indexOf('mode = "maximized"') >= 0);
        verify(WindowControls.maximizeDispatcher("0x1", 0).indexOf('action = "toggle"') >= 0);
        compare(WindowControls.maximizeDispatcher("0x1", 1), "fullscreen 1");
        // Hyprland 0.57 has no minimize dispatcher: hide parks the window on
        // a special workspace so it stays in the dock and alt-tab.
        verify(WindowControls.minimizeDispatcher("0x1", 0).indexOf('hl.dsp.window.move') === 0);
        verify(WindowControls.hideDispatcher("0x1").indexOf('special:minimized') >= 0);
        verify(WindowControls.tagDispatcher("0x1").indexOf('hl.dsp.window.tag') === 0);
        verify(WindowControls.untagDispatcher("0x1").indexOf('hl.dsp.window.clear_tags') === 0);
        verify(WindowControls.restoreDispatcher("0x1", 3).indexOf('workspace = 3') >= 0);
        verify(WindowControls.floatDispatcher("0x1", true).indexOf('action = "set"') >= 0);
        verify(WindowControls.floatDispatcher("0x1", false).indexOf('action = "unset"') >= 0);
    }

    function test_dispatchers_for_actions_have_a_native_fallback_second() {
        compare(WindowControls.dispatchersFor("maximize", "0x1").length, 2);
        compare(WindowControls.dispatchersFor("minimize", "0x1").length, 1);
        compare(WindowControls.dispatchersFor("close", "0x1").length, 0);
        compare(WindowControls.dispatchersFor("maximize", "0x1")[1], "fullscreen 1");
    }

    function test_state_for_is_what_the_verification_watches() {
        const normal = client("0x1", "kitty", { "fullscreen": 0 });
        const maximized = client("0x2", "kitty", { "fullscreen": 1 });
        const hidden = client("0x3", "kitty", { "hidden": true });

        compare(WindowControls.stateFor("maximize", normal), 0);
        compare(WindowControls.stateFor("maximize", maximized), 1);
        compare(WindowControls.stateFor("minimize", normal), false);
        compare(WindowControls.stateFor("minimize", hidden), true);
        compare(WindowControls.stateFor("maximize", null), null);
    }

    // ------------------------------------------------------------------
    // Demo mode (the playground must never dispatch into Hyprland)
    // ------------------------------------------------------------------

    function test_demo_mode_changes_only_the_mock_client() {
        WindowControls.demoReset("Playground");
        WindowControls.demoMode = true;

        compare(WindowControls.demoClient.floating, false);
        compare(WindowControls.displayType(), "tiling");

        // Close only writes to the log: no dispatcher, no real window.
        verify(WindowControls.close("0xdemo"));
        compare(WindowControls.demoLog.length, 1);
        verify(WindowControls.demoLog[0].indexOf("close") === 0);

        // Maximize toggles the mock's fullscreen flag.
        verify(WindowControls.maximize("0xdemo"));
        compare(WindowControls.demoClient.fullscreen, 1);
        verify(WindowControls.maximize("0xdemo"));
        compare(WindowControls.demoClient.fullscreen, 0);

        // Minimize hides the mock but it stays in the dock/alt-tab path.
        verify(WindowControls.minimize("0xdemo"));
        verify(WindowControls.isMinimized(WindowControls.displayClient));
        verify(WindowControls.restore("0xdemo"));
        verify(!WindowControls.isMinimized(WindowControls.displayClient));

        // Type changes update the mock and the log, never WindowMode config.
        verify(WindowControls.setType("floating", "0xdemo"));
        compare(WindowControls.displayType(), "floating");
        verify(WindowControls.setType("stacking", "0xdemo"));
        compare(WindowControls.displayType(), "stacking");
        verify(WindowControls.setType("span", "0xdemo"));
        compare(WindowControls.displayType(), "span");
        compare(WindowControls.nextType(WindowControls.displayType()), "floating");
        verify(WindowControls.cycleType("0xdemo"));
        compare(WindowControls.displayType(), "floating");

        WindowControls.demoMode = false;
        WindowControls.demoReset("Playground");
    }

    function test_demo_reset_restores_a_clean_mock() {
        WindowControls.demoMode = true;
        WindowControls.setType("span", "0xdemo");
        WindowControls.minimize("0xdemo");
        WindowControls.demoReset("Playground");

        compare(WindowControls.demoLog.length, 0);
        compare(WindowControls.demoClient.fullscreen, 0);
        verify(!WindowControls.isMinimized(WindowControls.demoClient));
        compare(WindowControls.displayType(), "tiling");

        WindowControls.demoMode = false;
    }

    // ------------------------------------------------------------------
    // Fallback candidate bookkeeping
    // ------------------------------------------------------------------

    function test_candidate_index_is_per_action() {
        WindowControls.maximizeCandidate = 0;
        WindowControls.minimizeCandidate = 0;
        compare(WindowControls.candidateIndex("maximize"), 0);
        compare(WindowControls.candidateIndex("minimize"), 0);

        WindowControls.setCandidateIndex("maximize", 1);
        compare(WindowControls.candidateIndex("maximize"), 1);
        compare(WindowControls.candidateIndex("minimize"), 0);

        // -1 marks a known-unsupported dispatcher for that one action only.
        WindowControls.setCandidateIndex("minimize", -1);
        compare(WindowControls.candidateIndex("minimize"), -1);
        compare(WindowControls.candidateIndex("maximize"), 1);

        // Restore the defaults for the rest of the suite and for other files.
        WindowControls.maximizeCandidate = 0;
        WindowControls.minimizeCandidate = 0;
    }
}
