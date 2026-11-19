pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Front-end for the user-level end4pc-vnc controller.
 *
 * The controller owns the config; this singleton only reads `status --json`
 * and sends JSON patches. Keeping the QML side away from the filesystem is
 * what prevents the old VNC theme hooks from racing the shell config.
 */
Singleton {
    id: root

    readonly property string helperPath: `${Quickshell.env("HOME") ?? ""}/.local/bin/end4pc-vnc`
    property bool helperAvailable: false
    property bool helperChecked: false
    property bool monitoring: false
    property bool busy: false
    property string lastError: ""
    property var status: ({})
    property var settings: ({})
    property var clients: []
    property var outputs: []
    property var monitors: []
    property var addresses: []
    property var detectedAddresses: []
    property var listenAddresses: []
    property var statusErrors: []
    property bool serviceActive: false
    property bool serviceEnabled: false
    property bool serviceInstalled: false
    property bool hasPassword: false
    property bool tlsReady: false
    property string fingerprint: ""
    property string headless: ""
    property string versionText: ""
    property string hostname: ""

    signal updated()

    property string applyPayload: ""
    property string passwordPayload: ""

    function refresh(): void {
        if (statusProc.running) return
        statusProc.running = true
    }

    function setStatus(s): void {
        if (!s || typeof s !== "object") return
        root.status = s
        root.settings = s.config ?? {}
        root.clients = s.clients ?? []
        root.outputs = s.outputs ?? []
        root.monitors = s.monitors ?? []
        root.addresses = s.addresses ?? []
        root.detectedAddresses = s.detected ?? []
        root.listenAddresses = s.listenAddresses ?? []
        root.statusErrors = s.errors ?? []
        root.serviceActive = !!s.serviceActive
        root.serviceEnabled = !!s.serviceEnabled
        root.serviceInstalled = !!s.serviceInstalled
        root.hasPassword = !!s.hasPassword
        root.tlsReady = !!s.tlsReady
        root.fingerprint = s.fingerprint ?? ""
        root.headless = s.headless ?? ""
        root.hostname = s.hostname ?? ""
        root.versionText = s.version?.wayvnc ?? ""
        root.helperAvailable = true
        root.updated()
    }

    function handleStatus(text): void {
        try {
            root.setStatus(JSON.parse(text))
            root.lastError = ""
        } catch (e) {
            root.lastError = "Cannot parse VNC status: " + e
        }
    }

    function handleActionResult(text, code, stderrText): void {
        let parsed = null
        try { parsed = JSON.parse(text) } catch (e) {}
        if (parsed && parsed.ok) {
            if (parsed.status) root.setStatus(parsed.status)
            root.lastError = ""
        } else if (code !== 0) {
            root.lastError = (parsed && parsed.error) || stderrText || `VNC action failed (${code})`
        }
        settleTimer.restart()
    }

    function apply(patch): void {
        if (root.busy) return
        root.busy = true
        root.lastError = ""
        root.applyPayload = JSON.stringify(patch)
        applyProc.stdinEnabled = true
        applyProc.running = true
    }

    function setPassword(password): void {
        if (root.busy || !password) return
        root.busy = true
        root.lastError = ""
        root.passwordPayload = password
        passwordProc.stdinEnabled = true
        passwordProc.running = true
    }

    function runAction(args): void {
        if (root.busy) return
        root.busy = true
        root.lastError = ""
        actionProc.command = [root.helperPath].concat(args)
        actionProc.running = true
    }

    function start(): void { root.runAction(["service", "start"]) }
    function stop(): void { root.runAction(["service", "stop"]) }
    function restart(): void { root.runAction(["service", "restart"]) }
    function setAutostart(enabled): void {
        root.runAction(["service", enabled ? "autostart-on" : "autostart-off"])
    }
    function regenerateCertificate(): void { root.runAction(["cert", "regenerate"]) }
    function outputSet(name): void { root.runAction(["output-set", name]) }
    function desktopName(name): void { root.runAction(["desktop-name", name]) }
    function disconnectClient(id): void { root.runAction(["disconnect", id]) }

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
                root.lastError = statusErr.text.trim() || `VNC status failed (${code})`
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
        }
    }

    Process {
        id: passwordProc
        command: [root.helperPath, "password"]
        onRunningChanged: {
            if (passwordProc.running) {
                passwordProc.write(root.passwordPayload + "\n")
                passwordProc.stdinEnabled = false
                root.passwordPayload = ""
            }
        }
        stdout: StdioCollector {
            id: passwordOut
        }
        stderr: StdioCollector {
            id: passwordErr
        }
        onExited: (code, exitStatus) => {
            root.busy = false
            root.handleActionResult(passwordOut.text, code, passwordErr.text.trim())
        }
    }

    IpcHandler {
        target: "vnc"

        function refresh(): void { root.refresh() }

        // Diagnostic endpoint used by the Settings page and by the CLI to
        // exercise the exact same apply path the UI uses.
        function applyCurrent(): void { root.apply(root.settings) }
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
        }
    }
}
