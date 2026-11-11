pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

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
        root.active = d.active === true;
        root.ssid = d.ssid ?? "";
        root.channel = d.channel ?? 0;
        root.freq = d.freq ?? 0;
        root.ip = d.ip ?? "";
        root.uplink = d.uplink ?? "";
        root.clients = Array.isArray(d.clients) ? d.clients : [];
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
