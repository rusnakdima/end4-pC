pragma Singleton
import qs.modules.common
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
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.inhibit = Persistent.states.idle.inhibit;
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // hypridle can be told to ignore Wayland, D-Bus or systemd inhibitors,
    // and a compositor may reject the Wayland inhibitor attached to a hidden
    // surface. A logind idle inhibitor is the one form hypridle honours in
    // every configuration, and it also covers compositors that do not honour
    // a Wayland inhibitor at all.
    Process {
        running: root.inhibit
        command: ["systemd-inhibit", "--what=idle", "--who=end4-pC",
            "--why=Keep system awake", "--mode=block", "sleep", "infinity"]
        onExited: (exitCode, exitStatus) => {
            if (root.inhibit && exitCode !== 0)
                console.warn(`Idle: logind inhibitor exited with code ${exitCode}`);
        }
    }

    Timer {
        interval: 500
        running: true
        onTriggered: root.inhibitorWindowReady = true
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
