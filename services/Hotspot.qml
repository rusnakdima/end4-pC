pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Hotspot state for the parallel STA+AP access point on the AIC8800.
 *
 * Every action is a call to the root helper /usr/local/bin/aic-hotspot
 * (NOPASSWD via sudo for this user) and the published state is that
 * helper's live JSON, so it only means something against the running
 * machine's radio.
 */
Singleton {
    id: root

    property bool active: false
    property bool busy: actionProc.running
    property string ssid: ""
    property int channel: 0
    property int freq: 0
    property string ip: ""
    property string uplink: ""
    property list<var> clients: []
    property string error: ""
    property bool supported: true

    // Client change tracking. `clientBaseline` is the last published snapshot;
    // an empty array alone cannot mean "not seeded yet", hence the flag.
    // `pendingDisconnects` holds rows that vanished in the previous poll, so a
    // disconnect is only announced if they are still absent in this one.
    property var clientBaseline: []
    property bool clientBaselineSeeded: false
    property var pendingDisconnects: []

    // Notify the user about an AP client change. The diff itself lives in the
    // pure, hosted-tested HotspotUtils helper; this only forwards it to notify-send.
    function notifyClientChange(client, connected) {
        if (!Config.options.hotspot.notifyClientChanges) return;
        const label = HotspotUtils.clientLabel(client);
        const ssid = root.ssid || Translation.tr("the hotspot");
        const summary = connected
            ? Translation.tr("Hotspot client connected")
            : Translation.tr("Hotspot client disconnected");
        const body = connected
            ? Translation.tr("%1 connected to %2").arg(label).arg(ssid)
            : Translation.tr("%1 disconnected from %2").arg(label).arg(ssid);
        Quickshell.execDetached(["notify-send", "-a", "Shell", summary, body]);
    }

    // Reconcile the current client snapshot with the previous one. Called only
    // from applyJson() on successful status polls while the AP is active.
    function trackClients(clientsNow) {
        // First status while active, or AP just started: seed silently so
        // devices that were already connected are not announced.
        if (!root.clientBaselineSeeded) {
            // Copy: root.clients is a live list<var> wrapper, so keeping the
            // reference would make the baseline mutate with the next poll.
            root.clientBaseline = Array.from(clientsNow);
            root.pendingDisconnects = [];
            root.clientBaselineSeeded = true;
            return;
        }

        const currentMacs = new Set(clientsNow.map(c => HotspotUtils.macOf(c)));
        const cancelledMacs = new Set();
        const stillPending = [];

        // Resolve disconnects queued by the previous poll.
        for (const pending of root.pendingDisconnects) {
            const mac = HotspotUtils.macOf(pending);
            if (currentMacs.has(mac)) {
                // It came back before we announced the disconnect: no event.
                cancelledMacs.add(mac);
            } else {
                root.notifyClientChange(pending, false);
            }
        }

        const change = HotspotUtils.diffClients(root.clientBaseline, clientsNow);

        for (const client of change.connected) {
            const mac = HotspotUtils.macOf(client);
            if (!cancelledMacs.has(mac)) root.notifyClientChange(client, true);
        }

        for (const client of change.disconnected) {
            const mac = HotspotUtils.macOf(client);
            if (!stillPending.some(entry => HotspotUtils.macOf(entry) === mac))
                stillPending.push(client);
        }
        root.pendingDisconnects = stillPending;
        root.clientBaseline = Array.from(clientsNow);
    }

    // The helper prints one JSON line per run. Only action runs (start/stop)
    // may overwrite `error`: the periodic status poll always reports
    // error:"" and must not wipe the message of a start that just failed.
    function applyJson(raw, isAction) {
        let line = "";
        for (const l of raw.split("\n")) {
            const t = l.trim();
            if (t.startsWith("{")) line = t;
        }
        if (line === "") return;
        let d;
        try {
            d = JSON.parse(line);
        } catch (e) {
            return;
        }
        const wasActive = root.active;
        root.active = d.active === true;
        root.ssid = d.ssid ?? "";
        root.channel = d.channel ?? 0;
        root.freq = d.freq ?? 0;
        root.ip = d.ip ?? "";
        root.uplink = d.uplink ?? "";
        root.clients = Array.isArray(d.clients) ? d.clients : [];

        // Track clients only against successful status JSON. Start/stop action
        // runs also print a status line: use them to seed/reset the baseline
        // silently, never to announce the devices that were already there.
        if (!root.active) {
            root.clientBaseline = [];
            root.pendingDisconnects = [];
            root.clientBaselineSeeded = false;
        } else if (!wasActive) {
            root.clientBaseline = Array.from(root.clients);
            root.pendingDisconnects = [];
            root.clientBaselineSeeded = true;
        } else {
            root.trackClients(root.clients);
        }

        if (isAction) {
            root.error = d.error ?? "";
            root.supported = d.error !== "driver refused second interface";
        }
    }

    function refresh() {
        if (statusProc.running) return;
        statusProc.running = true;
    }

    function toggle() {
        if (root.busy) return;
        if (root.active) root.stop();
        else root.start();
    }

    function start() {
        if (root.busy) return;
        actionProc.exec(["sudo", "-n", "/usr/local/bin/aic-hotspot", "start",
            Config.options.hotspot.ssid,
            Config.options.hotspot.passphrase,
            String(Config.options.hotspot.channel)]);
    }

    function stop() {
        if (root.busy) return;
        actionProc.exec(["sudo", "-n", "/usr/local/bin/aic-hotspot", "stop"]);
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 4000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: ["sudo", "-n", "/usr/local/bin/aic-hotspot", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyJson(text, false)
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: root.applyJson(text, true)
        }
        onExited: root.refresh()
    }
}
