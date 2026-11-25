import QtQuick
import QtTest
import "WaydroidUtils.js" as WaydroidUtils

/**
 * Tests for the pure helpers behind the Waydroid shell service.
 *
 * `waydroid status` is tab-separated and prints different subsets of keys
 * depending on the session state; `waydroid prop get sys.boot_completed`
 * returns "1" only once Android has actually finished booting. The shell UI
 * must derive its honesty labels from those two outputs without sudo.
 */
TestCase {
    id: testCase
    name: "WaydroidUtils"
    when: windowShown

    function test_status_parses_every_field() {
        const text = [
            "Session:\tRUNNING",
            "Container:\tRUNNING",
            "Vendor type:\tMAINLINE",
            "IP address:\tUNKNOWN",
            "Session user:\tdmitriy(1000)",
            "Wayland display:\twayland-1"
        ].join("\n");
        const s = WaydroidUtils.parseStatus(text);
        compare(s.session, "RUNNING");
        compare(s.container, "RUNNING");
        compare(s.vendorType, "MAINLINE");
        compare(s.ipAddress, "UNKNOWN");
        compare(s.sessionUser, "dmitriy(1000)");
        compare(s.waylandDisplay, "wayland-1");
    }

    function test_status_missing_keys_are_empty_strings() {
        const s = WaydroidUtils.parseStatus("Session:\tSTOPPED\nVendor type:\tMAINLINE\n");
        compare(s.session, "STOPPED");
        compare(s.container, "");
        compare(s.waylandDisplay, "");
    }

    function test_status_ignores_unrelated_output() {
        const s = WaydroidUtils.parseStatus("Warning: something\nSession:\tRUNNING\nContainer:\tSTOPPED\n");
        compare(s.session, "RUNNING");
        compare(s.container, "STOPPED");
    }

    function test_boot_completed_true_only_for_one() {
        compare(WaydroidUtils.parseBootCompleted("1\n"), true);
        compare(WaydroidUtils.parseBootCompleted("1"), true);
        compare(WaydroidUtils.parseBootCompleted("0\n"), false);
        compare(WaydroidUtils.parseBootCompleted(""), false);
        compare(WaydroidUtils.parseBootCompleted("Failed to get service waydroidplatform\n"), false);
    }

    function test_apps_available_requires_both_session_and_boot() {
        compare(WaydroidUtils.appsAvailable({ session: "RUNNING", container: "RUNNING" }, true), true);
        compare(WaydroidUtils.appsAvailable({ session: "RUNNING", container: "RUNNING" }, false), false);
        compare(WaydroidUtils.appsAvailable({ session: "RUNNING", container: "STOPPED" }, true), false);
    }

    function test_status_text_is_honest_when_guest_has_not_booted() {
        const s = WaydroidUtils.parseStatus("Session:\tRUNNING\nContainer:\tRUNNING\n");
        const text = WaydroidUtils.statusText(s, false);
        verify(text.includes("guest"));
    }
}
