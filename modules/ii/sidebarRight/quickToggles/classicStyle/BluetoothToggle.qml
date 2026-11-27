import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

QuickToggleButton {
    id: root
    visible: BluetoothStatus.available
    toggled: BluetoothStatus.enabled
    buttonIcon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
    onClicked: {
        BluetoothStatus.togglePower()
    }
    altAction: () => {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`])
        GlobalStates.sidebarRightOpen = false
    }

    // Small gear opens the Bluetooth page in Settings without changing the
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
                GlobalStates.settingsTarget = { page: "bluetooth" }
                GlobalStates.settingsOpen = true
            }
        }
    }

    StyledToolTip {
        text: Translation.tr("%1 | Right-click to configure").arg(
            (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Bluetooth"))
            + (BluetoothStatus.activeDeviceCount > 1 ? ` +${BluetoothStatus.activeDeviceCount - 1}` : "")
            )
    }
}
