import qs
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

AndroidQuickToggleButton {
    id: root
    
    toggleModel: NetworkToggle {}

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
}

