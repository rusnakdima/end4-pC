pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Bar-layout widget for the window controls.
 *
 * Add "Window Controls" to any bar layout from Settings → Bar → Bar layout.
 * It manages the focused window; the four buttons are minimize, maximize,
 * close and a type button that cycles Floating → Tiling → Stacking → Span.
 *
 * Minimize parks the window on the special:minimized workspace, so it stays
 * in the dock and alt-tab. Activating it from either place brings it back.
 */
Item {
    id: root

    implicitWidth: controls.implicitWidth + 4
    implicitHeight: Appearance.sizes.barHeight

    WindowControlsCluster {
        id: controls
        anchors.centerIn: parent
        address: WindowControls.activeAddress
        compact: true
        useMenu: false
        embedded: true
        reveal: "always"
    }
}
