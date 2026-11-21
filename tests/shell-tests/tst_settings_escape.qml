import QtQuick
import QtTest
import "modules/common/functions/SettingsEscape.js" as EscapeDecision

/**
 * Escape must never close the settings window: it is needed to cancel a
 * keybind edit. This tests the pure decision shared by the three handlers
 * (settings key scope, dashboard and keyboard page), not a copy of them.
 * Expected values are literal, hand-derived from the user-facing rule.
 */
TestCase {
    id: testCase
    name: "SettingsEscape"
    when: true

    function check(context, expected) {
        const actual = EscapeDecision.decide(context);
        compare(JSON.stringify(actual), JSON.stringify(expected));
    }

    function test_global_escape_never_closes_settings() {
        check({ source: "global" }, {
            closeSettings: false, accept: true,
            closeForm: false, stopCapture: false, back: false
        });
    }

    function test_dashboard_escape_keeps_preset_back_and_never_closes() {
        check({ source: "dashboard", isPresetsPage: true, hasSelection: true }, {
            closeSettings: false, accept: true,
            closeForm: false, stopCapture: false, back: true
        });
    }

    function test_dashboard_escape_without_selection_does_nothing_but_consume() {
        check({ source: "dashboard", isPresetsPage: true, hasSelection: false }, {
            closeSettings: false, accept: true,
            closeForm: false, stopCapture: false, back: false
        });
    }

    function test_capture_escape_stops_capture_and_consumes_event() {
        check({ source: "capture", capturing: true, formOpen: false }, {
            closeSettings: false, accept: true,
            closeForm: false, stopCapture: true, back: false
        });
    }

    function test_capture_escape_closes_form_when_no_capture_is_active() {
        check({ source: "capture", capturing: false, formOpen: true }, {
            closeSettings: false, accept: true,
            closeForm: true, stopCapture: false, back: false
        });
    }

    function test_capture_escape_without_form_or_capture_is_not_consumed() {
        check({ source: "capture", capturing: false, formOpen: false }, {
            closeSettings: false, accept: false,
            closeForm: false, stopCapture: false, back: false
        });
    }

    function test_unknown_source_does_nothing() {
        check({ source: "other" }, {
            closeSettings: false, accept: false,
            closeForm: false, stopCapture: false, back: false
        });
    }
}
