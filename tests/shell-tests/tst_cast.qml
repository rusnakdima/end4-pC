import QtQuick
import QtTest
import qs.services

/**
 * The Cast service must stay usable with no helper installed: it parses the
 * helper's JSON defensively and keeps its last known good state on failures.
 */
TestCase {
    id: testCase
    name: "Cast"
    when: true

    function test_helper_path_points_at_the_user_helper() {
        verify(Cast.helperPath.endsWith("/.local/bin/end4pc-cast"));
    }

    function test_backend_state_accepts_both_shapes() {
        verify(Cast.backendState(true));
        verify(!Cast.backendState(false));
        verify(Cast.backendState({ installed: true }));
        verify(Cast.backendState({ available: true }));
        verify(!Cast.backendState({ installed: false }));
        verify(!Cast.backendState("yes"));
    }

    function test_doctor_entries_are_normalised() {
        const entries = Cast.normaliseDoctor([
            { ok: true, label: "Wi-Fi Direct", detail: "ready" },
            { passed: false, name: "waycast", message: "not installed" }
        ]);
        compare(entries.length, 2);
        compare(entries[0].label, "Wi-Fi Direct");
        compare(entries[0].ok, true);
        compare(entries[1].label, "waycast");
        compare(entries[1].ok, false);
        compare(entries[1].detail, "not installed");
    }

    function test_malformed_doctor_is_an_empty_list() {
        compare(Cast.normaliseDoctor(null).length, 0);
        compare(Cast.normaliseDoctor("nope").length, 0);
    }

    function test_service_exposes_the_expected_actions() {
        for (const action of ["refresh", "apply", "discover", "start", "stop", "restart", "setLogLines"])
            verify(typeof Cast[action] === "function", action);
    }
}
