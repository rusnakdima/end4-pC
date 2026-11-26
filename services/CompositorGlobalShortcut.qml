import QtQuick
import Quickshell.Hyprland
import qs
import qs.services

Loader {
    id: root

    property string name: ""
    property string description: ""
    signal pressed()
    signal released()

    // Unloading the shortcut (rather than changing its name) is the only way
    // to stop a combo from firing while a keybind is being recorded: Quickshell
    // 0.3.2 fixes a GlobalShortcut's name at registration time.
    active: WM.compositor === "hyprland" && !GlobalStates.keybindCaptureArmed

    sourceComponent: GlobalShortcut {
        name: root.name
        description: root.description
        onPressed: root.pressed()
        onReleased: root.released()
    }
}
