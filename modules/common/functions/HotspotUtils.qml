pragma Singleton
import Quickshell

/**
 * Pure helpers for the access point's client list.
 *
 * Hotspot.qml publishes rows of {ip, mac, host} from the aic-hotspot status
 * helper. Connect/disconnect detection is a diff of two such snapshots; it is
 * kept here, free of any process or radio dependency, so it can be tested in
 * the hosted harness (tst_hotspot_clients.qml).
 */
Singleton {
    id: root

    /**
     * Hotspot.clients is a QML list<var>, which is array-like but not a JS
     * Array. Array.from handles both plain arrays and those wrappers.
     */
    function toArray(value) {
        if (value === null || value === undefined) return [];
        try {
            return Array.from(value);
        } catch (e) {
            return [];
        }
    }

    /** Normalised MAC used as the identity of a client across snapshots. */
    function macOf(client) {
        return String(client?.mac ?? "").trim().toLowerCase();
    }

    /** Human readable device name: the lease hostname, or the MAC as fallback. */
    function clientLabel(client) {
        const host = String(client?.host ?? "").trim();
        if (host !== "" && host !== "*") return host;
        return macOf(client);
    }

    /**
     * @param {Array} previous last published client snapshot
     * @param {Array} current  current client snapshot
     * @returns {{connected: Array, disconnected: Array}}
     * Disconnected entries are the previous rows, so the caller can still
     * label a device that is no longer in the current snapshot.
     */
    function diffClients(previous, current) {
        const before = toArray(previous);
        const after = toArray(current);

        const beforeByMac = new Map();
        for (const client of before) {
            const mac = macOf(client);
            if (mac !== "" && !beforeByMac.has(mac)) beforeByMac.set(mac, client);
        }
        const afterByMac = new Map();
        for (const client of after) {
            const mac = macOf(client);
            if (mac !== "" && !afterByMac.has(mac)) afterByMac.set(mac, client);
        }

        const connected = [];
        afterByMac.forEach((client, mac) => {
            if (!beforeByMac.has(mac)) connected.push(client);
        });
        const disconnected = [];
        beforeByMac.forEach((client, mac) => {
            if (!afterByMac.has(mac)) disconnected.push(client);
        });
        return { connected: connected, disconnected: disconnected };
    }
}
