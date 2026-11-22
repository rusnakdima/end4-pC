pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.ii.cheatsheet

/**
 * Small PowerToys-style desktop utilities.
 *
 * Find My Mouse polls the pointer for a couple of seconds and lets a layer
 * overlay draw highlight rings at the sampled positions.
 * Screen Ruler is a draggable measuring strip on the focused screen.
 * Awake and Always-On-Top are exposed here for IPC/keybind convenience; the
 * actual work is already done by Idle and Hyprland's window pin dispatcher.
 */
Singleton {
    id: root

    property bool findMouseActive: false
    property bool rulerActive: false
    property var cursorSamples: []

    readonly property int findMouseDuration: 2500

    function findMouse(): void {
        if (root.findMouseActive) return;
        root.cursorSamples = [];
        root.findMouseActive = true;
        findMouseProc.running = true;
        findMouseTimer.restart();
    }

    function stopFindMouse(): void {
        findMouseProc.running = false;
        root.findMouseActive = false;
    }

    function toggleRuler(): void {
        root.rulerActive = !root.rulerActive;
    }

    function toggleAwake(): void {
        Idle.toggleInhibit();
    }

    function toggleAlwaysOnTop(): void {
        Quickshell.execDetached(["bash", "-c", "hyprctl dispatch 'hl.dsp.window.pin()'"]);
    }

    Timer {
        id: findMouseTimer
        interval: root.findMouseDuration
        repeat: false
        onTriggered: root.stopFindMouse()
    }

    Process {
        id: findMouseProc
        command: ["bash", "-c", "for i in $(seq 1 60); do hyprctl cursorpos -j 2>/dev/null; sleep 0.04; done"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim().length === 0) return;
                try {
                    const point = JSON.parse(line);
                    const next = root.cursorSamples.concat([{ x: Number(point.x) || 0, y: Number(point.y) || 0 }]);
                    root.cursorSamples = next.slice(-8);
                } catch (error) {
                    // Ignore malformed lines from hyprctl.
                }
            }
        }
    }

    IpcHandler {
        target: "utilities"

        function findMouse(): void { root.findMouse() }
        function ruler(): void { root.toggleRuler() }
        function awake(): void { root.toggleAwake() }
        function alwaysOnTop(): void { root.toggleAlwaysOnTop() }
    }

    /**
     * Cheatsheet.qml owns quickshell:cheatsheetToggle/Open/Close, but only
     * WaffleFamily loads it. Instantiate it here for the default ii family so
     * the SUPER+Slash bind is live in both families. Gated on !waffle so the
     * waffle family's own PanelLoader stays the single instance (and there is
     * never a duplicate GlobalShortcut registration) while waffle is active.
     */
    Loader {
        active: Config.ready && Config.options.panelFamily !== "waffle"
        sourceComponent: Cheatsheet {}
    }

    CompositorGlobalShortcut {
        name: "findMouse"
        description: "Find My Mouse — highlight the pointer"
        onPressed: root.findMouse()
    }

    CompositorGlobalShortcut {
        name: "screenRuler"
        description: "Toggle the screen ruler"
        onPressed: root.toggleRuler()
    }

    /**
     * The ALT+F4 Hyprland bind is non-consuming and must never close the
     * window (ALT+F4 is reserved for Windows VMs). Its old raw code called
     * hl.exec_cmd(), which is a no-op on Hyprland 0.57.2, so the "wrong close
     * keybind" hint never appeared. The bind now dispatches this global
     * shortcut instead, and the notification is sent from QML — the same
     * bridge pattern used for the generated runCommand:<id> shortcuts.
     */
    function wrongCloseKeybind(): void {
        Quickshell.execDetached([
            "notify-send", "Wrong close keybind",
            "Super+Q to close. Use Alt+F4 for Windows VMs", "-a", "Hyprland"
        ]);
    }

    CompositorGlobalShortcut {
        name: "wrongCloseKeybind"
        description: "ALT+F4 hint — use Super+Q to close"
        onPressed: root.wrongCloseKeybind()
    }
}
