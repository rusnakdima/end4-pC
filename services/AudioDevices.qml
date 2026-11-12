pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * pavucontrol-style device data layer on top of pactl.
 *
 * quickshell's PwNode exposes no ports/profiles and node.audio is null for
 * idle devices, so per-device volume/mute/port and per-card profile data
 * come from pactl instead:
 *
 *  - `pactl list cards/sinks/sources` is parsed into `cards`/`sinks`/
 *    `sources` (name-keyed plain objects). Sources ending in `.monitor`
 *    are dropped; they never match a real input anyway.
 *  - `pactl subscribe` streams change events. Events are mapped to the
 *    ONE list that changed (`on sink #` → sinks only) and coalesced by a
 *    100 ms debounce, so a refresh spawns at most a single `pactl` — not
 *    the old 6-process full dump on every sink state flicker.
 *  - Parsed results are compared against the live state by signature
 *    (names, volume, mute, ports, profiles, defaults) and assigned ONLY
 *    when something actually changed. Sink IDLE/RUNNING churn therefore
 *    costs one pactl spawn and zero UI work — no rebinds, no combo model
 *    resets, no stutter while music plays or a slider is dragged.
 *
 * Every setter takes the pactl *name* (never the index: nodes are
 * recreated on profile/BT restarts; names are stable) and requests a
 * targeted refresh of its own kind, so the UI updates even for changes
 * `pactl subscribe` does not report (defaults are metadata, not objects).
 */
Singleton {
    id: root

    property var cards: []        // {name, description, activeProfile, profiles:[{name, description, available}]}
    property var sinks: []        // {name, description, volume, mute, ports:[{name, description, available}], activePort}
    property var sources: []
    property var outputNames: []  // stable delegate models: swap only on structure change
    property var inputNames: []
    property string defaultSinkName: ""
    property string defaultSourceName: ""
    property bool ready: false

    // Kinds pending for the next debounced refresh:
    // "cards" | "sinks" | "sources" | "defaults".
    property var pendingKinds: ({})

    // ------------------------------------------------------------- parsing

    function parseBlock(text) {
        const cards = [];
        const sinks = [];
        const sources = [];
        let cur = null;
        let kind = "";
        let inProfiles = false;
        let inPorts = false;

        for (const raw of text.split("\n")) {
            const header = raw.match(/^(Card|Sink|Source) #\d+$/);
            if (header) {
                kind = header[1];
                inProfiles = false;
                inPorts = false;
                if (kind === "Card") {
                    cur = {name: "", description: "", activeProfile: "", profiles: [], ports: []};
                    cards.push(cur);
                } else {
                    cur = {name: "", description: "", volume: 100, mute: false,
                        ports: [], activePort: "", flags: ""};
                    (kind === "Sink" ? sinks : sources).push(cur);
                }
                continue;
            }

            // Default markers arrive in their own refresh (no block context).
            if (raw.startsWith("__DEF_SINK__")) {
                root.defaultSinkName = raw.slice("__DEF_SINK__".length).trim();
                continue;
            }
            if (raw.startsWith("__DEF_SOURCE__")) {
                root.defaultSourceName = raw.slice("__DEF_SOURCE__".length).trim();
                continue;
            }

            if (cur === null) continue;

            const ind = raw.match(/^(\t+)(.*)$/);
            if (!ind) continue;               // column-0 noise (balance lines, ...)
            const level = ind[1].length;
            const body = ind[2];

            if (level >= 3) continue;         // port Properties / profile notes

            if (level === 2 && kind === "Card" && !inProfiles && !inPorts
                    && body.startsWith("device.description = ")) {
                cur.description = body.slice(21).replace(/^"|"$/g, "");
                continue;
            }

            if (level === 1) {
                if (body.startsWith("Profiles:")) { inProfiles = true; inPorts = false; continue; }
                if (body.startsWith("Ports:")) { inPorts = true; inProfiles = false; continue; }
                inProfiles = false;
                inPorts = false;

                if (body.startsWith("Name: ")) { cur.name = body.slice(6); continue; }
                if (body.startsWith("Description: ")) { cur.description = body.slice(13); continue; }
                if (body.startsWith("Mute: ")) { cur.mute = body.slice(6) === "yes"; continue; }
                if (body.startsWith("Flags: ")) { cur.flags = body.slice(7); continue; }
                if (body.startsWith("Volume: ")) {
                    const v = body.match(/\/ (\d+)%/);
                    if (v) cur.volume = Number(v[1]);
                    continue;
                }
                if (body.startsWith("Active Port: ")) { cur.activePort = body.slice(13); continue; }
                if (body.startsWith("Active Profile: ")) { cur.activeProfile = body.slice(16); continue; }
                continue;
            }

            // level 2: profile or port entries of the current section
            if (inProfiles) {
                const p = body.match(/^(\S+): (.*) \(sinks: \d+, sources: \d+, priority: \d+, available: (yes|no)\)$/);
                if (p) cur.profiles.push({name: p[1], description: p[2], available: p[3] === "yes"});
            } else if (inPorts) {
                const p = body.match(/^(\S+): (.*) \((.*)\)$/);
                if (p && !body.startsWith("Part of profile")) {
                    const tail = p[3];
                    const unavailable = tail.includes("not available") || tail.includes("available: no");
                    cur.ports.push({name: p[1], description: p[2], available: !unavailable});
                }
            }
        }

        // monitors are capture of an output, not an input device
        return {cards, sinks, sources: sources.filter(s => !s.name.endsWith(".monitor"))};
    }

    // ------------------------------------------------------- change detection

    function devSig(list) {
        return list.map(d => d.name + "|" + d.description + "|" + d.volume + "|" + d.mute
            + "|" + d.activePort + "|" + (d.flags ?? "")
            + "|" + d.ports.map(p => p.name + ":" + p.available).join(",")).join(";");
    }

    // Devices the panel offers: only those that actually let you change
    // the volume (pactl Flags advertise HW_VOLUME_CTRL/DECIBEL_VOLUME …).
    // Empty flags = a parse miss → assume capable (PipeWire software
    // volume exists on every real device) so nothing ever vanishes.
    function volumeCapable(d) {
        return !d.flags || d.flags.includes("VOLUME");
    }

    function cardsKey(cards) {
        return cards.map(c => c.name + "|" + c.description + "|" + c.activeProfile + "|"
            + c.profiles.map(p => p.name + ":" + p.available).join(",")).join(";");
    }

    // -------------------------------------------------------------- refresh

    function requestRefresh(kind) {
        if (kind === "all") {
            root.pendingKinds["cards"] = true;
            root.pendingKinds["sinks"] = true;
            root.pendingKinds["sources"] = true;
            root.pendingKinds["defaults"] = true;
        } else {
            root.pendingKinds[kind] = true;
        }
        debounce.restart();
    }

    function defaultsCmd() {
        return "echo __DEF_SINK__ $(pactl get-default-sink); echo __DEF_SOURCE__ $(pactl get-default-source)";
    }

    function flush() {
        const kinds = Object.keys(root.pendingKinds);
        root.pendingKinds = ({});
        if (kinds.length === 0) return;
        listProc.kinds = kinds;
        if (kinds.length === 1 && kinds[0] === "defaults") {
            listProc.command = ["bash", "-c", root.defaultsCmd()];
        } else if (kinds.length === 1) {
            listProc.command = ["pactl", "list", kinds[0]];
        } else {
            listProc.command = ["bash", "-c", kinds
                .map(k => k === "defaults" ? root.defaultsCmd() : `pactl list ${k}`)
                .join("; ")];
        }
        listProc.running = false;
        listProc.running = true;
    }

    // --------------------------------------------------------------- lookup

    function sink(name) {
        for (const s of root.sinks) if (s.name === name) return s;
        return null;
    }

    function source(name) {
        for (const s of root.sources) if (s.name === name) return s;
        return null;
    }

    function isDefault(name) {
        return name === root.defaultSinkName || name === root.defaultSourceName;
    }

    function icon(name, isOutput) {
        if (name.startsWith("bluez_")) return isOutput ? "headphones" : "mic";
        if (name.includes("hdmi")) return "settings_input_hdmi";
        if (name.includes("easyeffects")) return "graphic_eq";
        if (!isOutput) return "mic";
        if (name.includes("usb")) return "usb";
        return "volume_up";
    }

    // --------------------------------------------------------------- write

    function run(args) {
        Quickshell.execDetached(["pactl"].concat(args));
    }

    function setSinkVolume(name, pct) {
        root.run(["set-sink-volume", name, Math.max(0, Math.round(pct)) + "%"]);
        root.requestRefresh("sinks");
    }
    function setSinkMute(name, mute) {
        root.run(["set-sink-mute", name, mute ? "1" : "0"]);
        root.requestRefresh("sinks");
    }
    function setSinkPort(name, port) {
        root.run(["set-sink-port", name, port]);
        root.requestRefresh("sinks");
    }
    function setSourceVolume(name, pct) {
        root.run(["set-source-volume", name, Math.max(0, Math.round(pct)) + "%"]);
        root.requestRefresh("sources");
    }
    function setSourceMute(name, mute) {
        root.run(["set-source-mute", name, mute ? "1" : "0"]);
        root.requestRefresh("sources");
    }
    function setSourcePort(name, port) {
        root.run(["set-source-port", name, port]);
        root.requestRefresh("sources");
    }
    function setCardProfile(cardName, profile) {
        root.run(["set-card-profile", cardName, profile]);
        root.requestRefresh("cards");
        // Profile switches recreate the sink/source nodes.
        root.requestRefresh("sinks");
        root.requestRefresh("sources");
        root.requestRefresh("defaults");
    }
    function setDefaultSink(name) {
        root.run(["set-default-sink", name]);
        root.requestRefresh("defaults");
    }
    function setDefaultSource(name) {
        root.run(["set-default-source", name]);
        root.requestRefresh("defaults");
    }

    // -------------------------------------------------------------- procs

    Process {
        id: listProc
        property var kinds: []
        property string text: ""
        stdout: SplitParser {
            onRead: (line) => {
                if (line.length > 0) listProc.text += line + "\n";
            }
        }
        onExited: {
            const kinds = listProc.kinds;
            const parsed = root.parseBlock(listProc.text);
            listProc.text = "";
            // Assign only what actually changed: unchanged data keeps its
            // object identity, so no binding re-evaluates and the UI stays
            // completely still (this is the anti-frieze core).
            if (kinds.includes("cards")
                    && root.cardsKey(parsed.cards) !== root.cardsKey(root.cards)) {
                root.cards = parsed.cards;
            }
            if (kinds.includes("sinks")) {
                if (root.devSig(parsed.sinks) !== root.devSig(root.sinks)) {
                    root.sinks = parsed.sinks;
                }
                const outs = parsed.sinks.filter(root.volumeCapable).map(s => s.name);
                if (outs.join("\n") !== root.outputNames.join("\n")) root.outputNames = outs;
            }
            if (kinds.includes("sources")) {
                if (root.devSig(parsed.sources) !== root.devSig(root.sources)) {
                    root.sources = parsed.sources;
                }
                const ins = parsed.sources.filter(root.volumeCapable).map(s => s.name);
                if (ins.join("\n") !== root.inputNames.join("\n")) root.inputNames = ins;
            }
            root.ready = true;
        }
    }

    Process {
        id: subscribeProc
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: (line) => {
                // Only refresh the object class that actually changed:
                // "Event 'change' on sink #57" → sinks (sink-input would not
                // match: the regex requires the "#" right after the class).
                const m = line.match(/on (sink|source|card) #/);
                if (m) root.requestRefresh(m[1] + "s");
                else if (line.includes("settings")) root.requestRefresh("defaults");
            }
        }
        onExited: restartProc.restart()
    }

    Timer {
        id: debounce
        interval: 100
        onTriggered: root.flush()
    }

    Timer {
        id: restartProc
        interval: 1500
        onTriggered: subscribeProc.running = true
    }

    // Self-healing poll while subscribe is down.
    Timer {
        interval: 3000
        repeat: true
        running: !subscribeProc.running
        onTriggered: root.requestRefresh("all")
    }

    Component.onCompleted: {
        // A hot-reload orphans the previous engine's subscribe process;
        // sweep stale ones (the bracket pattern avoids matching this very
        // command). If the sweep races our own subscribe, onExited →
        // restartProc brings it back within 1.5 s.
        Quickshell.execDetached(["bash", "-c", "pkill -f 'pact[l] subscribe' || true"]);
        root.requestRefresh("all");
    }
}
