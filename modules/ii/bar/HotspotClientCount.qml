import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * AP icon with its connected-client counter, following the exact pattern of
 * NotificationUnreadCount.qml: a small themed circle pinned to the icon's
 * top-right corner. Kept declarative - the diff lives in HotspotUtils.
 */
MaterialSymbol {
    id: root
    property color contentColor: Appearance.colors.colOnLayer1
    property bool contentColorOverridden: false
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3 || Config.options.bar.cornerStyle === 4

    text: "wifi_tethering"
    iconSize: Appearance.font.pixelSize.larger
    color: root.contentColorOverridden ? root.contentColor : (root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1)

    Rectangle {
        id: clientPing
        visible: Hotspot.active && Hotspot.clients.length > 0 && Config.options.bar.indicators.hotspot.showClientCount
        anchors {
            right: parent.right
            top: parent.top
        }
        radius: Appearance.rounding.full
        color: root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        z: 1

        implicitHeight: Math.max(clientCounterText.implicitWidth, clientCounterText.implicitHeight)
        implicitWidth: implicitHeight

        StyledText {
            id: clientCounterText
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colLayer0
            text: Hotspot.clients.length
        }
    }
}
