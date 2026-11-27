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
    toggled: Network.wifiStatus !== "disabled"
    buttonIcon: Network.materialSymbol
    onClicked: Network.toggleWifi()
    altAction: () => {
        Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`])
        GlobalStates.sidebarRightOpen = false
    }

    // Small gear opens the Wi-Fi page in Settings without changing the
    // tile's own toggle or right-click action.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        width: 18
        height: 18
        radius: 9
        z: 5
        color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.2)
        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: 13
            text: "settings"
            color: Appearance.colors.colOnSurfaceVariant
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                GlobalStates.settingsTarget = { page: "wifi" }
                GlobalStates.settingsOpen = true
            }
        }
    }

    StyledToolTip {
        text: Translation.tr("%1 | Right-click to configure").arg(Network.networkName)
    }
}
