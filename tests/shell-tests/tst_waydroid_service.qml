import QtQuick
import QtTest
import qs.services

/**
 * The Waydroid singleton must publish honest state: a running user session
 * with a dead guest is NOT "apps ready". Keep this in the hosted shell tests
 * because the real service needs Quickshell's Process/Singleton types.
 */
TestCase {
    id: testCase
    name: "WaydroidService"
    when: true

    function test_running_session_without_guest_is_not_ready() {
        Waydroid.applyStatus("Session:\tRUNNING\nContainer:\tRUNNING\n");
        Waydroid.applyBoot("")
        compare(Waydroid.session, "RUNNING")
        compare(Waydroid.container, "RUNNING")
        compare(Waydroid.bootCompleted, false)
        compare(Waydroid.appsAvailable, false)
        compare(Waydroid.statusText, "Session running, guest not booted")
    }

    function test_boot_completed_marks_apps_ready() {
        Waydroid.applyStatus("Session:\tRUNNING\nContainer:\tRUNNING\n")
        Waydroid.applyBoot("1\n")
        compare(Waydroid.bootCompleted, true)
        compare(Waydroid.appsAvailable, true)
        compare(Waydroid.statusText, "Apps ready")
    }

    function test_stopped_container_is_reported() {
        Waydroid.applyStatus("Session:\tRUNNING\nContainer:\tSTOPPED\n")
        Waydroid.applyBoot("")
        compare(Waydroid.container, "STOPPED")
        compare(Waydroid.appsAvailable, false)
        compare(Waydroid.statusText, "Container stopped")
    }

    // A failed start must stay visible until the next user action. The 4s
    // status poll must not wipe the error message the user needs to see.
    function test_start_error_survives_status_refresh() {
        Waydroid.lastError = ""
        Waydroid.handleActionResult(1, "waydroid-user-start: venus socket missing\n")
        Waydroid.handleStatus("Session:\tSTOPPED\nContainer:\tSTOPPED\n")
        compare(Waydroid.lastError, "waydroid-user-start: venus socket missing")
    }

    // A bounded action that times out has no stderr; the user still needs a
    // clear reason instead of an empty error label.
    function test_timed_out_action_reports_timeout() {
        Waydroid.lastError = ""
        Waydroid.handleActionResult(124, "")
        compare(Waydroid.lastError, "Waydroid action timed out")
    }
}
