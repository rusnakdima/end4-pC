import QtQuick
import QtTest
import qs.modules.common.functions

/**
 * Tests for the pure AP client diff helper.
 *
 * Hotspot.qml publishes the live client list of the access point as
 * {ip, mac, host} rows. The connect/disconnect notifications are derived by
 * diffing two of those snapshots, so identity, ordering and label fallbacks
 * must be deterministic without a running radio.
 */
TestCase {
    id: testCase
    name: "HotspotClients"
    when: true

    function client(mac, host = "", ip = "") {
        return { "mac": mac, "host": host, "ip": ip };
    }

    function test_empty_snapshots_have_no_changes() {
        const change = HotspotUtils.diffClients([], []);
        compare(change.connected.length, 0);
        compare(change.disconnected.length, 0);
    }

    function test_a_new_mac_is_reported_as_connected() {
        const added = client("AA:BB:CC:DD:EE:01", "phone", "192.168.1.2");
        const change = HotspotUtils.diffClients([], [added]);
        compare(change.connected.length, 1);
        compare(change.connected[0].mac, added.mac);
        compare(change.disconnected.length, 0);
    }

    function test_a_missing_mac_is_reported_as_disconnected() {
        const removed = client("AA:BB:CC:DD:EE:01", "phone", "192.168.1.2");
        const change = HotspotUtils.diffClients([removed], []);
        compare(change.connected.length, 0);
        compare(change.disconnected.length, 1);
        // The previous row is returned so the caller can still label it.
        compare(change.disconnected[0].host, "phone");
        compare(change.disconnected[0].ip, "192.168.1.2");
    }

    function test_simultaneous_add_and_remove() {
        const removed = client("AA:BB:CC:DD:EE:01", "old-phone");
        const added = client("AA:BB:CC:DD:EE:02", "new-phone");
        const change = HotspotUtils.diffClients([removed], [added]);
        compare(change.connected.length, 1);
        compare(change.connected[0].mac, added.mac);
        compare(change.disconnected.length, 1);
        compare(change.disconnected[0].mac, removed.mac);
    }

    function test_reordering_the_same_clients_is_not_a_change() {
        const a = client("AA:BB:CC:DD:EE:01", "a");
        const b = client("AA:BB:CC:DD:EE:02", "b");
        const change = HotspotUtils.diffClients([a, b], [b, a]);
        compare(change.connected.length, 0);
        compare(change.disconnected.length, 0);
    }

    function test_mac_identity_is_case_insensitive() {
        const previous = client("AA:BB:CC:DD:EE:01", "phone");
        const current = client("aa:bb:cc:dd:ee:01", "phone");
        const change = HotspotUtils.diffClients([previous], [current]);
        compare(change.connected.length, 0);
        compare(change.disconnected.length, 0);
        compare(HotspotUtils.macOf(current), "aa:bb:cc:dd:ee:01");
    }

    function test_label_prefers_the_host_and_falls_back_to_the_normalised_mac() {
        compare(HotspotUtils.clientLabel(client("AA:BB:CC:DD:EE:01", "phone")), "phone");
        // The helper uses one normalised lowercase MAC for identity and label.
        compare(HotspotUtils.clientLabel(client("AA:BB:CC:DD:EE:01", "")), "aa:bb:cc:dd:ee:01");
        compare(HotspotUtils.clientLabel(client("AA:BB:CC:DD:EE:01", "*")), "aa:bb:cc:dd:ee:01");
    }

    function test_duplicate_macs_are_counted_once() {
        const c = client("AA:BB:CC:DD:EE:01", "phone");
        const change = HotspotUtils.diffClients([], [c, c]);
        compare(change.connected.length, 1);
    }

    function test_qml_list_wrappers_are_accepted_as_snapshots() {
        // Hotspot.clients is a list<var>: array-like but not a JS Array.
        const a = client("AA:BB:CC:DD:EE:01", "phone");
        const wrapper = { 0: a, length: 1 };
        const change = HotspotUtils.diffClients(wrapper, wrapper);
        compare(change.connected.length, 0);
        compare(change.disconnected.length, 0);
        const added = HotspotUtils.diffClients([], wrapper);
        compare(added.connected.length, 1);
    }

    function test_a_blank_mac_is_not_treated_as_a_client() {
        const blank = client("", "unknown");
        const valid = client("AA:BB:CC:DD:EE:01", "phone");
        const change = HotspotUtils.diffClients([], [blank, valid]);
        compare(change.connected.length, 1);
        compare(change.connected[0].mac, valid.mac);
    }
}
