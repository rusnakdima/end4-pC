pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio?.volume ?? 0
    
    function friendlyDeviceName(node) {
        // node.name as last resort: quickshell's property dict is partial
        // for nodes it has not negotiated, so description may be absent.
        return (node?.nickname || node?.description || (node ? String(node.name) : "") || Translation.tr("Unknown"));
    }
    function appNodeDisplayName(node) {
        return (node.properties["application.name"] || node.description || node.name)
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    // Devices are matched by direction plus a media-class/name test, never
    // by `node.audio` (null while a device is suspended) and not by
    // media.class alone: quickshell's property dict is only partially
    // populated for nodes it has not negotiated, and media.class is missing
    // on exactly the idle devices the dropdown must offer (HDMI, analog, a
    // quiet BT sink). Filter nodes (EasyEffects) are absent from
    // Pipewire.nodes entirely but appear as link-group endpoints, so they
    // are collected from there as well.
    function devices(isSink) {
        const seen = {};
        const out = [];
        const want = (node) => {
            if (!node || node.isStream || node.isSink !== isSink) return false;
            const name = String(node.name ?? "");
            if (name.startsWith("ee_")) return false; // EasyEffects internal stages
            const mediaClass = node.properties?.["media.class"] ?? "";
            if (mediaClass) return mediaClass.startsWith("Audio/");
            // media.class not arrived yet: accept real device name shapes,
            // reject drivers (Dummy/Freewheel), midi and camera nodes.
            return /^(alsa|bluez)_(input|output)\./.test(name) || name.startsWith("easyeffects_");
        };
        const add = (node) => {
            if (!want(node) || seen[node.id]) return;
            seen[node.id] = true;
            out.push(node);
        };
        for (const node of Pipewire.nodes.values) add(node);
        for (const group of Pipewire.linkGroups.values) {
            add(group.source);
            add(group.target);
        }
        return out;
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function toggleMute() {
        if (!Audio.sink?.audio) return;
        Audio.sink.audio.muted = !Audio.sink.audio.muted;
    }

    function toggleMicMute() {
        if (!Audio.source?.audio) return;
        Audio.source.audio.muted = !Audio.source.audio.muted;
    }

    function incrementVolume() {
        if (!Audio.sink?.audio) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02;
        Audio.sink.audio.volume = Math.min(1, Math.round((currentVolume + step) * 100) / 100);
    }
    
    function decrementVolume() {
        if (!Audio.sink?.audio) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02;
        Audio.sink.audio.volume = Math.max(0, Math.round((currentVolume - step) * 100) / 100);
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Per-stream device routing (via pipewire-pulse's pactl move-sink-input /
    // move-source-output). The pulse index of a stream is its PipeWire
    // object.serial, and the pulse name of a device is its node.name.
    // "Reset" is just a move back to the current default device: no pinning
    // property is written, so the stream keeps following default changes.
    property bool routeAvailable: false

    function streamSerial(node) {
        const serial = node?.properties?.["object.serial"];
        return (serial === undefined || serial === null) ? null : String(serial);
    }

    function defaultDevice(isSink) {
        return isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
    }

    // Device a stream links into directly, read live from the link groups
    // (playback: stream -> device, capture: device -> stream). This is often
    // a filter node (e.g. easyeffects_sink), not the device you hear.
    function directStreamDevice(node) {
        if (!node) return null;
        for (const group of Pipewire.linkGroups.values) {
            if (node.isSink) {
                if (group.source === node && group.target && !group.target.isStream) return group.target;
            } else if (group.target === node && group.source && !group.source.isStream) {
                return group.source;
            }
        }
        return null;
    }

    // Hardware devices carry a device.api (alsa, bluez5, ...); filter and
    // virtual nodes (easyeffects_sink and its internal chain) do not.
    // device.api can be missing from quickshell's partial property dict on
    // idle devices, so fall back to the well-known device name shapes.
    function isHardwareDevice(node) {
        if (!node) return false;
        if (node.properties?.["device.api"]) return true;
        return /^(alsa|bluez)_(input|output)\./.test(String(node.name ?? ""));
    }

    // Next link along the audio path after a filter node: playback follows
    // the node's outgoing link, capture the incoming one.
    function chainNextDevice(node, playback) {
        for (const group of Pipewire.linkGroups.values) {
            if (playback) {
                if (group.source === node && group.target && !group.target.isStream) return group.target;
            } else if (group.target === node && group.source && !group.source.isStream) {
                return group.source;
            }
        }
        return null;
    }

    // Device a stream's audio really ends on: follows filter chains
    // (stream -> easyeffects_sink -> ... -> SN6140 Analog) until a hardware
    // device is reached, so the UI shows what you hear instead of the
    // filter an effects processor puts in front of it.
    // A chain that stalls inside a filter (EasyEffects tears its internal
    // links down while idle) returns null: the caller then reports the
    // stream as following the default instead of flapping between the
    // filter's name and the real device as audio starts and stops.
    function streamDevice(node) {
        let dev = root.directStreamDevice(node);
        if (!dev) return null;
        const playback = node?.isSink ?? true;
        let depth = 0;
        while (depth++ < 6 && !root.isHardwareDevice(dev)) {
            const next = root.chainNextDevice(dev, playback);
            if (!next || next === dev) return null;
            dev = next;
        }
        return dev;
    }

    function deviceIcon(node) {
        if (!node) return "speaker";
        if (!node.isSink) return "mic";
        const about = `${node.nickname ?? ""} ${node.description ?? ""} ${node.name ?? ""}`.toLowerCase();
        if (/headset|headphone|bluez|wireless/.test(about)) return "headphones";
        if (/hdmi|display|tv|monitor/.test(about)) return "tv";
        return "speaker";
    }

    // device = null resets the stream to the system default device.
    //
    // Two steps, because WirePlumber re-resolves targets from the
    // `default` metadata on every rescan (new stream, device change):
    //   1. pactl moves the live link right now;
    //   2. the metadata pin records the choice, so later rescans keep it
    //      instead of falling back to a stale stored target. A reset drops
    //      the pin and writes the "-1" follow-default marker (the same
    //      value linking-utils writes when a stream sits on the default).
    // EasyEffects re-pins its own streams within ~400ms; the caller detects
    // that bounce and tells the user instead of silently pretending.
    function moveStreamToDevice(node, device) {
        const serial = root.streamSerial(node);
        if (!serial) {
            console.warn("Audio: cannot route stream without object.serial:", node?.name ?? "?");
            return false;
        }
        const target = device ?? root.defaultDevice(node.isSink);
        if (!target || !target.name) {
            console.warn("Audio: no target device to route stream to");
            return false;
        }
        const verb = node.isSink ? "move-sink-input" : "move-source-output";
        Quickshell.execDetached(["pactl", verb, serial, String(target.name)]);

        const subject = String(node.id ?? "");
        if (subject) {
            if (device) {
                const targetSerial = String(target.properties?.["object.serial"] ?? "");
                if (targetSerial) {
                    Quickshell.execDetached(["pw-metadata", "-n", "default", subject,
                        "target.object", targetSerial, "Spa:Id"]);
                }
            } else {
                Quickshell.execDetached(["pw-metadata", "-d", "-n", "default", subject, "target.object"]);
                Quickshell.execDetached(["pw-metadata", "-n", "default", subject,
                    "target.node", "-1", "Spa:Id"]);
            }
        }
        return true;
    }

    // Hide the per-stream device UI when pipewire-pulse/pactl is unavailable
    Process {
        id: routeProbe
        command: ["pactl", "--version"]
        running: true
        stdout: StdioCollector {
            id: routeProbeOutput
            onStreamFinished: root.routeAvailable = routeProbeOutput.text.includes("pactl")
        }
        onExited: (exitCode) => {
            if (exitCode === 0) root.routeAvailable = true;
        }
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
