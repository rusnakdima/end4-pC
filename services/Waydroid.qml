pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "../modules/common/functions/WaydroidUtils.js" as WaydroidUtils

/**
 * Waydroid state for the shell, driven entirely by the normal user session.
 *
 * Nothing here uses sudo. `waydroid status` and `waydroid prop get` both talk
 * to the user's D-Bus session, and the only privileged setup is already done
 * once by optional/waydroid/install-waydroid.sh (user Venus service + the
 * whitelisted /usr/local/bin/waydroid-root NOPASSWD helper).
 *
 * Published state is deliberately honest: a running session/container with a
 * guest that has not finished booting is reported as "guest not booted", not
 * as apps being ready.
 */
Singleton {
    id: root

    readonly property string helperPath: `${Quickshell.env("HOME") ?? ""}/.local/bin/waydroid-user-start`
    readonly property string desktopGenPath: `${Quickshell.env("HOME") ?? ""}/.config/quickshell/end4-pC/scripts/waydroid-desktop-gen.sh`

    property bool monitoring: true
    property bool busy: actionProc.running || uiProc.running || desktopProc.running
    property string lastError: ""

    property var status: ({})
    property string session: ""
    property string container: ""
    property string vendorType: ""
    property string ipAddress: ""
    property string sessionUser: ""
    property string waylandDisplay: ""
    property bool bootCompleted: false
    property bool appsAvailable: false
    property string statusText: "Stopped"

    signal updated()

    function recompute(): void {
        root.appsAvailable = WaydroidUtils.appsAvailable(root.status, root.bootCompleted)
        root.statusText = WaydroidUtils.statusText(root.status, root.bootCompleted)
        root.updated()
    }

    function applyStatus(text): void {
        const parsed = WaydroidUtils.parseStatus(text)
        root.status = parsed
        root.session = parsed.session ?? ""
        root.container = parsed.container ?? ""
        root.vendorType = parsed.vendorType ?? ""
        root.ipAddress = parsed.ipAddress ?? ""
        root.sessionUser = parsed.sessionUser ?? ""
        root.waylandDisplay = parsed.waylandDisplay ?? ""
        root.recompute()
    }

    function applyBoot(text): void {
        root.bootCompleted = WaydroidUtils.parseBootCompleted(text)
        root.recompute()
    }

    function refresh(): void {
        if (!statusProc.running) statusProc.running = true
        if (!bootProc.running) bootProc.running = true
    }

    function handleStatus(text): void {
        // Keep a start/action error visible: the status poll runs every 4s and
        // would otherwise erase the message before the user can read it.
        root.applyStatus(text)
    }

    function handleBoot(text): void {
        root.applyBoot(text)
    }

    function handleActionResult(code, stderrText): void {
        // `timeout` exits 124 with no stderr when an action hangs; show a
        // useful reason instead of leaving an empty error label.
        if (code === 124) {
            root.lastError = "Waydroid action timed out"
        } else if (code !== 0 && stderrText.trim()) {
            root.lastError = stderrText.trim()
        }
        refreshTimer.restart()
    }

    function start(): void {
        if (root.busy) return
        root.lastError = ""
        // Bound every action: a hung start/stop would keep `busy` true and
        // lock out every other control in the panel.
        actionProc.command = ["timeout", "30", root.helperPath]
        actionProc.running = true
    }

    function stop(): void {
        if (root.busy) return
        root.lastError = ""
        actionProc.command = ["timeout", "30", "waydroid", "session", "stop"]
        actionProc.running = true
    }

    function openFullUI(): void {
        if (root.busy) return
        uiProc.running = true
    }

    function regenerateDesktops(): void {
        if (root.busy) return
        desktopProc.running = true
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.monitoring
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshTimer
        interval: 1200
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: ["waydroid", "status"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: root.handleStatus(statusOut.text)
        }
        stderr: StdioCollector { id: statusErr }
        onExited: (code) => {
            if (code !== 0 && statusErr.text.trim())
                root.lastError = statusErr.text.trim()
        }
    }

    Process {
        id: bootProc
        command: ["timeout", "5", "waydroid", "prop", "get", "sys.boot_completed"]
        stdout: StdioCollector {
            id: bootOut
            onStreamFinished: root.handleBoot(bootOut.text)
        }
        stderr: StdioCollector { id: bootErr }
    }

    Process {
        id: actionProc
        command: []
        stdout: StdioCollector { id: actionOut }
        stderr: StdioCollector { id: actionErr }
        onExited: (code) => root.handleActionResult(code, actionErr.text)
    }

    Process {
        id: uiProc
        command: ["timeout", "30", "waydroid", "show-full-ui"]
        stdout: StdioCollector { id: uiOut }
        stderr: StdioCollector { id: uiErr }
        onExited: (code) => root.handleActionResult(code, uiErr.text)
    }

    Process {
        id: desktopProc
        command: ["timeout", "30", root.desktopGenPath]
        stdout: StdioCollector { id: desktopOut }
        stderr: StdioCollector { id: desktopErr }
        onExited: (code) => root.handleActionResult(code, desktopErr.text)
    }

    IpcHandler {
        target: "waydroid"
        function refresh(): void { root.refresh() }
        function start(): void { root.start() }
        function stop(): void { root.stop() }
        function openFullUI(): void { root.openFullUI() }
        function status(): string {
            return JSON.stringify({
                session: root.session,
                container: root.container,
                bootCompleted: root.bootCompleted,
                appsAvailable: root.appsAvailable,
                statusText: root.statusText
            })
        }
    }

    Component.onCompleted: root.refresh()
}
