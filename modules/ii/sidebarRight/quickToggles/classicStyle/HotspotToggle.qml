import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarRight.quickToggles
import qs
import QtQuick
import Quickshell
import Quickshell.Io

QuickToggleButton {
    toggled: Hotspot.active
    buttonIcon: "wifi_tethering"
    onClicked: Hotspot.toggle()
    StyledToolTip {
        text: Translation.tr("Hotspot access point | Right-click to manage")
    }
}
