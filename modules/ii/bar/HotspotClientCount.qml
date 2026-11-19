pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Badge for the bar's wifi_tethering icon: how many clients are connected to
 * the shell's access point. Follows the NotificationUnreadCount precedent:
 * a small themed circle pinned to the icon corner, shown only when relevant.
 * Kept declarative on purpose - the change detection lives in HotspotUtils.
 */
Rectangle {
    id: root
    property color contentColor: Appearance.colors.colOnLayer1
    property bool contentColorOverridden: false
    property bool isMaterial: false

    readonly property bool showCount: Config.options.bar.indicators.hotspot.showClientCount
        && Hotspot.active && Hotspot.clients.length > 0

    visible: showCount
    radius: Appearance.rounding.full
    color: root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
    implicitWidth: Math.max(countText.implicitWidth, countText.implicitHeight) + 2
    implicitHeight: implicitWidth
    z: 1

    StyledText {
        id: countText
        anchors.centerIn: parent
        font.pixelSize: Appearance.font.pixelSize.smallest - 2
        font.features: { "tnum": 1 }
        color: root.isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
        text: Hotspot.clients.length
    }
}
