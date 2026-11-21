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

    function snapshotState() {
        return {
            config: Cast.config, backends: Cast.backends, session: Cast.session,
            sinks: Cast.sinks, doctor: Cast.doctor, logTail: Cast.logTail,
            versionText: Cast.versionText, helperAvailable: Cast.helperAvailable,
            lastError: Cast.lastError
        };
    }

    function restoreState(s) {
        Cast.config = s.config;
        Cast.backends = s.backends;
        Cast.session = s.session;
        Cast.sinks = s.sinks;
        Cast.doctor = s.doctor;
        Cast.logTail = s.logTail;
        Cast.versionText = s.versionText;
        Cast.helperAvailable = s.helperAvailable;
        Cast.lastError = s.lastError;
    }

    function test_status_error_is_surfaced() {
        const saved = snapshotState();
        Cast.setStatus({ error: "no Wi-Fi Direct sinks found", config: {}, session: {}, sinks: [], doctor: [] });
        compare(Cast.lastError, "no Wi-Fi Direct sinks found");
        restoreState(saved);
    }

    function test_failed_action_error_is_surfaced_even_with_exit_code_zero() {
        const saved = snapshotState();
        // The helper always exits 0 so it can emit JSON on every path; the
        // error arrives as ok:false and must still reach the UI.
        Cast.handleActionResult(JSON.stringify({ ok: false, error: "waycast is not installed" }), 0, "");
        compare(Cast.lastError, "waycast is not installed");
        restoreState(saved);
    }

    function test_successful_action_note_is_surfaced() {
        const saved = snapshotState();
        Cast.handleActionResult(JSON.stringify({ ok: true, error: "fluxcast target not passed" }), 0, "");
        compare(Cast.lastError, "fluxcast target not passed");
        restoreState(saved);
    }

    function test_successful_action_clears_stale_error() {
        const saved = snapshotState();
        Cast.lastError = "stale error";
        Cast.handleActionResult(JSON.stringify({ ok: true, error: "", sinks: [] }), 0, "");
        compare(Cast.lastError, "");
        restoreState(saved);
    }

    function test_wrapped_status_payload_is_applied() {
        const saved = snapshotState();
        const payload = JSON.stringify({
            ok: true, error: "",
            status: { config: { networkMode: "local" }, session: { active: false }, sinks: [], doctor: [] }
        });
        Cast.handleActionResult(payload, 0, "");
        compare(Cast.config.networkMode, "local");
        restoreState(saved);
    }
}
