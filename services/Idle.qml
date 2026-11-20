pragma Singleton
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * Keeps the session out of the idle state ("Keep awake") and restores the
 * persisted toggle state.
 */
Singleton {
    id: root

    property bool inhibit: false

    // Hyprland checks the window an inhibitor is attached to once, when the
    // inhibitor is created, and does not re-check it when a layer surface
    // maps. Waiting for the first frames keeps that check valid for a state
    // that was restored at startup.
    property bool inhibitorWindowReady: false

    Component.onCompleted: {
        root.inhibit = Persistent.states.idle.inhibit;
        root.applyInhibit();
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.inhibit = Persistent.states.idle.inhibit;
            root.applyInhibit();
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
        root.applyInhibit();
    }

    // hypridle can be told to ignore Wayland, D-Bus or systemd inhibitors,
    // and a compositor may reject the Wayland inhibitor attached to a hidden
    // surface. A logind idle inhibitor is the one form hypridle honours in
    // every configuration, and it also covers compositors that do not honour
    // a Wayland inhibitor at all.
    //
    // The lock is held by a fixed-name user unit instead of a Process owned by
    // this shell. A shell reload used to orphan the old systemd-inhibit child
    // with its lock still held, so every reload added another permanent
    // "Keep system awake" lock and idle timeouts stopped firing altogether.
    // systemd now owns the lifetime (teardown at logout, one unit name), and
    // the unit's ExecStartPre reaps any locks left by older shell versions.
    readonly property string inhibitorUnit: "end4pc-keep-awake.service"

    function applyInhibit() {
        Quickshell.execDetached(["systemctl", "--user",
            root.inhibit ? "start" : "stop", root.inhibitorUnit])
    }

    Timer {
        interval: 500
        running: true
        onTriggered: root.inhibitorWindowReady = true
    }

    // PowerToys "Awake"-style external control.
    IpcHandler {
        target: "awake"

        function toggle(): void { root.toggleInhibit() }
        function enable(): void { root.toggleInhibit(true) }
        function disable(): void { root.toggleInhibit(false) }
        function status(): bool { return root.inhibit }
    }

    CompositorGlobalShortcut {
        name: "awakeToggle"
        description: "Toggle Keep Awake (Caffeine)"
        onPressed: root.toggleInhibit()
    }

    IdleInhibitor {
        id: idleInhibitor
        enabled: root.inhibit && root.inhibitorWindowReady
        // An inhibitor needs a surface the compositor can consider important.
        // A 1x1 window on the background layer is mapped immediately and does
        // not reserve any screen space.
        window: PanelWindow {
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:idle-inhibitor"
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
