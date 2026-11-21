pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Front-end for the user-level end4pc-cast controller.
 *
 * The controller owns the config; this singleton only reads its JSON status
 * and sends JSON patches. Keeping the QML side away from the filesystem is
 * what prevents the shell from racing the helper over config state.
 */
Singleton {
    id: root

    readonly property string helperPath: `${Quickshell.env("HOME") ?? ""}/.local/bin/end4pc-cast`
    property bool helperAvailable: false
    property bool helperChecked: false
    property bool monitoring: false
    property bool busy: false
    property string lastError: ""
    property int logLines: 50

    // Mirrors the helper's `status --json` payload.
    property var config: ({})
    property var backends: ({ waycast: false, fluxcast: false })
    property var session: ({})
    property var sinks: []
    property var doctor: []
    property string logTail: ""
    property string versionText: ""

    signal updated()

    property string applyPayload: ""
    property var pendingActions: []

    function refresh(): void {
        if (statusProc.running) return
        statusProc.running = true
    }

    function backendState(value): bool {
        if (typeof value === "boolean") return value
        if (value && typeof value === "object")
            return !!(value.available ?? value.ok ?? value.installed ?? value.ready ?? false)
        return false
    }

    function normaliseDoctor(entries): var {
        if (!Array.isArray(entries)) return []
        return entries.map(entry => ({
            ok: entry?.ok ?? entry?.passed ?? true,
            label: entry?.label ?? entry?.name ?? entry?.title ?? "",
            detail: entry?.detail ?? entry?.message ?? entry?.description ?? ""
        }))
    }

    function setStatus(s): void {
        if (!s || typeof s !== "object") return
        const b = s.backends ?? {}
        root.config = s.config ?? {}
        root.backends = {
            waycast: root.backendState(b.waycast),
            fluxcast: root.backendState(b.fluxcast)
        }
        root.session = s.session ?? {}
        root.sinks = Array.isArray(s.sinks) ? s.sinks : []
        root.doctor = root.normaliseDoctor(s.doctor)
        root.logTail = s.logTail ?? ""
        root.versionText = String(s.helperVersion ?? s.version ?? "")
        root.helperAvailable = true
        // The helper uses `error` for hard failures AND for informational
        // notes (e.g. "no Wi-Fi Direct sinks found"). Show them instead of
        // dropping them on the floor. Never clear a previous error here:
        // actions clear lastError when they start, and the 5 s status poll
        // must not wipe a message the user still needs to read.
        const note = String(s.error ?? "").trim()
        if (note !== "")
            root.lastError = note
        root.updated()
    }

    function handleStatus(text): void {
        try {
            root.setStatus(JSON.parse(text))
        } catch (e) {
            // A failed parse must never clobber the last known good state.
            root.lastError = "Cannot parse Cast status: " + e
        }
    }

    function handleActionResult(text, code, stderrText): void {
        let parsed = null
        let parseFailed = false
        try { parsed = JSON.parse(text) } catch (e) { parseFailed = !!text?.trim() }
        // Helpers either wrap the new state in `status` or return it flat.
        const payload = parsed?.status && typeof parsed.status === "object" ? parsed.status : parsed
        if (payload && (payload.config || payload.session || payload.sinks || payload.backends))
            root.setStatus(payload)
        const note = String(parsed?.error ?? "").trim()
        if (parsed && parsed.ok) {
            // Success may still carry a note; an empty note clears stale errors.
            root.lastError = note
        } else if (parseFailed) {
            root.lastError = "Cannot parse Cast action response: " + text
        } else if (code !== 0) {
            root.lastError = note || stderrText || `Cast action failed (${code})`
        } else if (parsed) {
            // IMPORTANT: the helper always exits 0 (it must emit JSON on every
            // path), so ok:false failures arrive with code === 0. Reading the
            // error only in the `code !== 0` branch hid every start/discover
            // failure from the user.
            root.lastError = note || stderrText || "Cast action failed"
        }
        settleTimer.restart()
    }

    function handleLogResult(text, code, stderrText): void {
        let parsed = null
        let parseFailed = false
        try { parsed = JSON.parse(text) } catch (e) { parseFailed = !!text?.trim() }
        if (typeof parsed === "string") {
            root.logTail = parsed
            root.lastError = ""
        } else if (parsed && parsed.ok) {
            root.logTail = parsed.logTail ?? parsed.log ?? ""
            root.lastError = ""
        } else if (parseFailed) {
            root.lastError = "Cannot parse Cast log response: " + text
        } else if (code !== 0) {
            root.lastError = (parsed && parsed.error) || stderrText || `Cast log failed (${code})`
        }
        settleTimer.restart()
    }

    function apply(patch): void {
        if (root.busy) return
        root.busy = true
        root.lastError = ""
        try {
            root.applyPayload = JSON.stringify(patch ?? {})
        } catch (e) {
            root.applyPayload = "{}"
            root.lastError = "Cannot encode Cast settings: " + e
        }
        applyProc.stdinEnabled = true
        applyProc.running = true
    }

    function runAction(args): void {
        // An apply (e.g. picking a sink) is usually followed immediately by
        // start()/discover(). Queue those so they are not dropped while the
        // apply process still owns `busy`.
        if (root.busy) {
            root.pendingActions = root.pendingActions.concat([args])
            return
        }
        root.busy = true
        root.lastError = ""
        actionProc.command = [root.helperPath].concat(args)
        actionProc.running = true
    }

    function drainQueue(): void {
        if (root.busy || root.pendingActions.length === 0) return
        const next = root.pendingActions[0]
        root.pendingActions = root.pendingActions.slice(1)
        root.runAction(next)
    }

    function start(): void { root.runAction(["start"]) }
    function stop(): void { root.runAction(["stop"]) }
    function restart(): void { root.runAction(["restart"]) }
    function discover(mode): void { root.runAction(["discover", mode]) }

    function setLogLines(n): void {
        root.logLines = Math.max(1, Math.min(2000, Math.floor(Number(n) || 50)))
        if (!logProc.running) logProc.running = true
        // Some helpers size logTail in the status payload instead of having
        // a dedicated `log` command; refreshing covers that case too.
        root.refresh()
    }

    onMonitoringChanged: {
        if (root.monitoring) root.refresh()
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.monitoring
        onTriggered: root.refresh()
    }

    Timer {
        id: settleTimer
        interval: 1200
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: [root.helperPath, "status"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: root.handleStatus(statusOut.text)
        }
        stderr: StdioCollector {
            id: statusErr
        }
        onExited: (code, exitStatus) => {
            root.helperChecked = true
            root.helperAvailable = code !== 127
            if (code !== 0)
                root.lastError = statusErr.text.trim() || `Cast status failed (${code})`
        }
    }

    Process {
        id: applyProc
        command: [root.helperPath, "apply", "--stdin"]
        onRunningChanged: {
            if (applyProc.running) {
                applyProc.write(root.applyPayload + "\n")
                applyProc.stdinEnabled = false
                root.applyPayload = ""
            }
        }
        stdout: StdioCollector {
            id: applyOut
        }
        stderr: StdioCollector {
            id: applyErr
        }
        onExited: (code, exitStatus) => {
            root.busy = false
            root.handleActionResult(applyOut.text, code, applyErr.text.trim())
            root.drainQueue()
        }
    }

    Process {
        id: logProc
        command: [root.helperPath, "log", String(root.logLines)]
        stdout: StdioCollector {
            id: logOut
        }
        stderr: StdioCollector {
            id: logErr
        }
        onExited: (code, exitStatus) => {
            root.handleLogResult(logOut.text, code, logErr.text.trim())
        }
    }

    IpcHandler {
        target: "cast"

        function refresh(): void { root.refresh() }

        // Diagnostic endpoint used by the Settings page and by the CLI to
        // exercise the exact same apply path the UI uses.
        function applyCurrent(): void { root.apply(root.config) }
    }

    Process {
        id: actionProc
        command: []
        stdout: StdioCollector {
            id: actionOut
        }
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: (code, exitStatus) => {
            root.busy = false
            root.handleActionResult(actionOut.text, code, actionErr.text.trim())
            root.drainQueue()
        }
    }
}
