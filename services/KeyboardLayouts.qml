pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Compositor-independent source of the active keyboard layout.
 *
 * Hyprland: polled from `hyprctl devices -j` because Quickshell 0.3.2
 * does not export a HyprlandXkb type. Niri: reuses services/NiriXkb.qml.
 */
Singleton {
    id: root

    readonly property bool isNiri: WM.compositor === "niri"

    property string hyprlandCode: ""
    property string hyprlandName: ""
    property var hyprlandLayoutNames: []

    readonly property string currentLayoutCode: root.isNiri
        ? (NiriXkb.currentLayoutCode ?? "")
        : root.hyprlandCode
    readonly property string currentLayoutName: root.isNiri
        ? (NiriXkb.currentLayoutName ?? "")
        : root.hyprlandName
    readonly property var layoutNames: root.isNiri
        ? (NiriXkb.layoutNames ?? [])
        : root.hyprlandLayoutNames

    Process {
        id: devicesProc
        running: false
        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: {
                if (root.isNiri) return;
                try {
                    const parsed = JSON.parse(devicesCollector.text);
                    const keyboards = (parsed.keyboards ?? []).filter(k => k && k.layout);
                    if (keyboards.length === 0) return;

                    // Prefer the "main" keyboard; fall back to the first one.
                    let active = keyboards.find(k => k.main);
                    if (!active) active = keyboards[0];

                    const codes = (active.layout ?? "").split(",").map(s => s.trim()).filter(s => s.length > 0);
                    const idx = Math.max(0, Math.min(active.active_layout_index ?? 0, Math.max(0, codes.length - 1)));
                    root.hyprlandCode = codes.length > 0 ? codes[idx] : "";
                    root.hyprlandName = active.active_keymap && active.active_keymap.length > 0
                        ? active.active_keymap
                        : root.hyprlandCode;
                    root.hyprlandLayoutNames = codes;
                } catch (e) {
                    console.log("[KeyboardLayouts] devices parse error: " + e);
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 1000
        repeat: true
        running: !root.isNiri
        onTriggered: devicesProc.running = true
    }

    Component.onCompleted: {
        if (!root.isNiri) devicesProc.running = true;
    }
}
