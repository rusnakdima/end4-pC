import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.ii.sidebarRight.notifications
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    WindowGlass {
        anchors.fill: parent
        glassEnabled: (parent?.color.a ?? 0) > 0
        cardRadius: parent?.radius ?? 0
        tint: parent?.color ?? 'transparent'
    }
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    // The collapsible cards all wear the same hairline.
    border.width: 1
    border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.55)
    // The list clips itself, but the card is the thing with the rounded
    // corners: a half-height spoiler must never paint its body outside them.
    clip: true

    // Spoiler state, stored with the sidebar's other view state
    // (Persistent.states.sidebar.bottomGroup.collapsed is the precedent).
    // Unlike the other cards this one used to be ReorderableColumn's fill
    // slot, stretching with the leftover panel height. It now keeps a size
    // of its own - header + margins when collapsed, one fixed card when
    // expanded - so the notification area no longer changes height with the
    // screen, and the sidebar scrolls when the sections do not fit.
    readonly property bool collapsed: Persistent.states.sidebar.notifications.collapsed
    property int expandedHeight: 320
    implicitHeight: collapsed ? header.implicitHeight + 10 : expandedHeight

    CollapsibleSectionHeader {
        id: header
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 5
        }
        headerIcon: "notifications"
        title: Translation.tr("Notifications")
        collapsed: root.collapsed
        // Write straight back into the caller's binding source; the header
        // only reports the tap, it never assigns to a bound property itself.
        onCollapseToggled: Persistent.states.sidebar.notifications.collapsed = !Persistent.states.sidebar.notifications.collapsed
    }

    NotificationList { // List, empty placeholder and the mute/count/clear row
        visible: !root.collapsed
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 5
        }
    }
}
