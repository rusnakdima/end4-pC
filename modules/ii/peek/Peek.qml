pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import qs.modules.common
import qs.services
import qs.modules.ii.peek

/**
 * Owns the Peek panel window. All state and the global trigger live in
 * services/Peek; this scope only keeps the layer alive while open.
 */
Scope {
    id: root

    // A stuck popup must never survive a shell reload.
    Component.onCompleted: {
        GlobalStates.peekOpen = false;
    }

    Loader {
        active: Config.ready && GlobalStates.peekOpen
        sourceComponent: PeekPanel {}
    }
}
