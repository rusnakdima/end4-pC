pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common
import qs.services
import qs.modules.ii.advancedPaste

/**
 * Owns the Advanced Paste popup window. The service (services/AdvancedPaste)
 * holds all state and the global trigger; this scope only keeps the layer
 * surface alive while the popup is open.
 */
Scope {
    id: root

    // A stuck popup must never survive a shell reload and hold the keyboard.
    Component.onCompleted: {
        GlobalStates.advancedPasteOpen = false;
    }

    Loader {
        active: Config.ready && GlobalStates.advancedPasteOpen
        sourceComponent: AdvancedPastePanel {}
    }
}
