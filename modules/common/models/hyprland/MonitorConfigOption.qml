pragma ComponentBehavior: Bound
import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.functions
import "../"

NestableObject {
    id: root

    property var monitors: []
    property var _pendingChanges: ({})

    // Windows-style projection state. The pre-projection layout is kept per
    // output name so a mode switch can restore exactly what was there before,
    // including after a compositor reload replaced the live monitor objects.
    property string projectionMode: ""
    property string projectionPlacement: "right"
    property var _baseByName: ({})
    property var _projectionQueue: []
    property var _saveDone: null
    property bool _applyingProjection: false
    property string _lastProjectionSignature: ""

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/monitor_configurator.py")
    readonly property string capsScriptPath: Quickshell.shellPath("scripts/hyprland/monitor_caps.py")
    readonly property string projectionScriptPath: Quickshell.shellPath("scripts/hyprland/projection_state.py")
    readonly property string monitorsLuaPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/monitors.lua`)

    Component.onCompleted: {
        fetchProc.running = true
        readStateProc.running = true
    }

    Connections {
        target: Hyprland
        enabled: WM.compositor === "hyprland"
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorlayout", "configreloaded"].includes(event.name))
                refreshTimer.restart()
        }
    }

    Timer {
        id: refreshTimer
        interval: 300
        repeat: false
        onTriggered: fetchProc.running = true
    }

    function updateMonitor(index, changes) {
        let m = root.monitors.slice()
        m[index] = Object.assign({}, m[index], changes)
        root.monitors = m

        let pending = Object.assign({}, root._pendingChanges)
        pending[index] = Object.assign({}, pending[index] || {}, changes)
        root._pendingChanges = pending
    }

    function _mergeByName(patchByName) {
        root.monitors = root.monitors.map(mon => {
            const patch = patchByName[mon.name]
            return patch ? Object.assign({}, mon, patch) : mon
        })
    }

    function _modeToLua(m) {
        const parts = m.currentMode.match(/(\d+)x(\d+)@([\d.]+)Hz/)
        return parts ? `${parts[1]}x${parts[2]}@${parseFloat(parts[3])}` : m.currentMode
    }

    function _fieldsToWrite(m, changedKeys) {
        const setPairs = {}
        const resetKeys = []

        if (changedKeys.has("disabled")) {
            if (m.disabled) setPairs["disabled"] = "1"
            else resetKeys.push("disabled")
        }
        if (changedKeys.has("x") || changedKeys.has("y")) {
            setPairs["position"] = `${m.x}x${m.y}`
        }
        if (changedKeys.has("currentMode") || changedKeys.has("width") || changedKeys.has("height") || changedKeys.has("refreshRate")) {
            setPairs["mode"] = root._modeToLua(m)
        }
        if (changedKeys.has("scale")) setPairs["scale"] = m.scale
        if (changedKeys.has("transform")) {
            if (m.transform && m.transform !== 0) setPairs["transform"] = m.transform
            else resetKeys.push("transform")
        }
        if (changedKeys.has("mirror")) {
            if (m.mirror && m.mirror !== "") setPairs["mirror"] = m.mirror
            else resetKeys.push("mirror")
        }
        if (changedKeys.has("bitdepth")) {
            if (m.bitdepth) setPairs["bitdepth"] = m.bitdepth
            else resetKeys.push("bitdepth")
        }
        if (changedKeys.has("cm")) {
            if (m.cm && m.cm !== "auto") setPairs["cm"] = m.cm
            else resetKeys.push("cm")
        }
        if (changedKeys.has("sdrBrightness")) setPairs["sdrbrightness"] = m.sdrBrightness
        if (changedKeys.has("sdrSaturation")) setPairs["sdrsaturation"] = m.sdrSaturation
        if (changedKeys.has("minLuminance")) setPairs["min_luminance"] = m.minLuminance
        if (changedKeys.has("maxLuminance")) setPairs["max_luminance"] = m.maxLuminance
        if (changedKeys.has("maxAvgLuminance")) setPairs["max_avg_luminance"] = m.maxAvgLuminance
        if (changedKeys.has("sdrMinLuminance")) setPairs["sdr_min_luminance"] = m.sdrMinLuminance
        if (changedKeys.has("sdrMaxLuminance")) setPairs["sdr_max_luminance"] = m.sdrMaxLuminance
        if (changedKeys.has("vrr")) setPairs["vrr"] = m.vrr ? "1" : "0"

        return { setPairs, resetKeys }
    }

    function save(index, onDone) {
        const m = root.monitors[index]
        if (!m || !m.name) {
            if (onDone) onDone()
            return
        }

        const changed = root._pendingChanges[index]
        if (!changed) {
            if (onDone) onDone()
            return
        }
        const changedKeys = new Set(Object.keys(changed))
        const { setPairs, resetKeys } = root._fieldsToWrite(m, changedKeys)

        let pending = Object.assign({}, root._pendingChanges)
        delete pending[index]
        root._pendingChanges = pending

        if (Object.keys(setPairs).length === 0 && resetKeys.length === 0) {
            if (onDone) onDone()
            return
        }

        let args = ["python3", root.configuratorScriptPath, "--file", root.monitorsLuaPath, "--output", m.name]
        for (const key in setPairs) args.push("--set", key, String(setPairs[key]))
        for (const key of resetKeys) args.push("--reset", key)

        root._saveDone = onDone ?? null
        saveProc.command = args
        saveProc.running = true
    }

    function applyMonitor(m) {
        if (!m || !m.name) return

        const base = `${m.name},${m.currentMode},${m.x}x${m.y},${m.scale}`
        const transform = (m.transform && m.transform !== 0) ? `,transform,${m.transform}` : ""
        const mirror = (m.mirror && m.mirror !== "") ? `,mirror,${m.mirror}` : ""
        applyProc.command = ["hyprctl", "keyword", "monitor",
            m.disabled ? `${m.name},disable` : `${base}${transform}${mirror}`]
        applyProc.running = true
    }

    function applyAndSave(index) {
        root.applyMonitor(root.monitors[index])
        root.save(index)
    }

    // ---- Windows-style projection -------------------------------------

    function snapshotLayout() {
        const bases = Object.assign({}, root._baseByName)
        for (const m of root.monitors) {
            if (!m || !m.name || bases[m.name]) continue
            bases[m.name] = {
                baseMode: m.currentMode,
                baseX: m.x,
                baseY: m.y,
                baseScale: m.scale,
                baseTransform: m.transform
            }
        }
        root._baseByName = bases
        return bases
    }

    function applyProjection(mode, placement) {
        if (!mode || mode === "") return
        const patches = ProjectionUtils.project(root.monitors, mode, placement)
        if (patches.length === 0) return
        root._applyingProjection = true
        root._projectionQueue = patches.slice()
        root._applyNextProjection()
    }

    function _applyNextProjection() {
        if (root._projectionQueue.length === 0) {
            root._applyingProjection = false
            root._lastProjectionSignature = root._signature()
            reloadProc.running = true
            return
        }
        const patch = root._projectionQueue.shift()
        const index = root.monitors.findIndex(m => m.name === patch.name)
        if (index < 0) {
            root._applyNextProjection()
            return
        }
        root.updateMonitor(index, patch.changes)
        root.applyMonitor(root.monitors[index])
        root.save(index, () => root._applyNextProjection())
    }

    function setProjection(mode, placement) {
        root.projectionMode = mode
        root.projectionPlacement = placement || "right"
        const bases = root.snapshotLayout()
        writeStateProc.command = ["python3", root.projectionScriptPath, "--set",
            mode, root.projectionPlacement, JSON.stringify(bases)]
        writeStateProc.running = true
        root.applyProjection(mode, root.projectionPlacement)
    }

    function clearProjection() {
        root.projectionMode = ""
        writeStateProc.command = ["python3", root.projectionScriptPath, "--set", "", root.projectionPlacement, "{}"]
        writeStateProc.running = true
    }

    function _signature() {
        return root.projectionMode + "|" + root.projectionPlacement + "|" +
            root.monitors.map(m =>
                `${m.name}:${m.currentMode}:${m.x}:${m.y}:${m.disabled}:${m.mirror ?? ""}`).join(",")
    }

    // A plug/unplug or a compositor reload must restore the chosen mode, but
    // the reload that follows our own apply must not start an apply loop.
    function _maybeRestoreProjection() {
        if (!root.projectionMode || root.monitors.length === 0 || root._applyingProjection) return
        if (root._signature() === root._lastProjectionSignature) return
        restoreTimer.restart()
    }

    function saveHdr(index) {
        root.save(index)
    }

    function logicalWidth(m) {
        return (m.transform === 1 || m.transform === 3) ? m.height : m.width
    }

    function logicalHeight(m) {
        return (m.transform === 1 || m.transform === 3) ? m.width : m.height
    }

    Process {
        id: fetchProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text).map(m => ({
                        mirror:        m.mirrorOf ?? m.mirror ?? "",
                        name:          m.name,
                        description:   m.description,
                        width:         m.width,
                        height:        m.height,
                        refreshRate:   m.refreshRate,
                        x:             m.x,
                        y:             m.y,
                        scale:         m.scale,
                        transform:     m.transform ?? 0,
                        disabled:      m.disabled,
                        availableModes: m.availableModes,
                        currentMode:   `${m.width}x${m.height}@${m.refreshRate.toFixed(2)}Hz`,
                        cm:            m.colorManagementPreset ?? "auto",
                        sdrBrightness: m.sdrBrightness ?? 1.0,
                        sdrSaturation: m.sdrSaturation ?? 1.0,
                        sdrMinLuminance: m.sdrMinLuminance ?? 0,
                        sdrMaxLuminance: m.sdrMaxLuminance ?? 0,
                        vrr:           m.vrr ?? false,
                        bitdepth:        null,
                        minLuminance:    null,
                        maxLuminance:    null,
                        maxAvgLuminance: null,

                        hdrSupported: null,
                        maxBpc:       null,
                    }))
                    // Reattach the layout captured before the active
                    // projection mode overwrote the live values.
                    root.monitors = root.monitors.map(m =>
                        Object.assign({}, m, root._baseByName[m.name] ?? {}))
                    root._maybeRestoreProjection()
                    if (root.monitors.length > 0) {
                        capsProc.command = ["python3", root.capsScriptPath].concat(root.monitors.map(mon => mon.name))
                        capsProc.running = true
                        dumpProc.command = ["python3", root.configuratorScriptPath, "--file", root.monitorsLuaPath, "--dump-all"]
                        dumpProc.running = true
                    }
                } catch(e) {
                    console.log("[MonitorConfig] Error parseando JSON:", e)
                }
            }
        }
    }

    Process {
        id: capsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const caps = JSON.parse(text)
                    let patch = {}
                    for (const name in caps) {
                        patch[name] = { hdrSupported: caps[name].hdr, maxBpc: caps[name].maxBpc }
                    }
                    root._mergeByName(patch)
                } catch(e) {
                    console.log("[MonitorConfig] Error parsing caps JSON:", e)
                }
            }
        }
    }

    Process {
        id: dumpProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const dump = JSON.parse(text)
                    let patch = {}
                    for (const name in dump) {
                        const d = dump[name]
                        patch[name] = {
                            bitdepth:        d.bitdepth ?? null,
                            minLuminance:    d.min_luminance ?? null,
                            maxLuminance:    d.max_luminance ?? null,
                            maxAvgLuminance: d.max_avg_luminance ?? null,
                        }
                    }
                    root._mergeByName(patch)
                } catch(e) {
                    console.log("[MonitorConfig] Error parsing monitors.lua dump JSON:", e)
                }
            }
        }
    }

    Process { id: applyProc }

    Process {
        id: saveProc
        onRunningChanged: {
            if (running) return
            if (root._saveDone) {
                const done = root._saveDone
                root._saveDone = null
                done()
            } else {
                reloadProc.running = true
            }
        }
    }

    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
    }

    Process {
        id: readStateProc
        command: ["python3", root.projectionScriptPath, "--get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const saved = JSON.parse(text)
                    root.projectionMode = saved.mode ?? ""
                    root.projectionPlacement = saved.placement ?? "right"
                    root._baseByName = saved.bases ?? {}
                    root._maybeRestoreProjection()
                } catch (e) {
                    console.log("[MonitorConfig] Error reading projection state:", e)
                }
            }
        }
    }

    Process { id: writeStateProc }

    Timer {
        id: restoreTimer
        interval: 800
        repeat: false
        onTriggered: {
            root._lastProjectionSignature = root._signature()
            root.applyProjection(root.projectionMode, root.projectionPlacement)
        }
    }
}
