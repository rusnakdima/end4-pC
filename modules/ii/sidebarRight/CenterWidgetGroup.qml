import qs.modules.common
import qs.modules.common.widgets
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
    // The list clips itself, but the card is the thing with the rounded
    // corners: a half-height spoiler must never paint its body outside them.
    clip: true

    // Spoiler state, stored with the sidebar's other view state
    // (Persistent.states.sidebar.bottomGroup.collapsed is the precedent).
    // While this is collapsed the card is no longer ReorderableColumn's
    // fillKey, so it has to report a real height of its own - it used to
    // report 0 and get away with it only because the filler is always shown
    // regardless of its natural height. Header + the 5 px margin above and
    // below it is the whole card when collapsed; when expanded the column
    // stretches the card to the leftover space and this number is unused.
    readonly property bool collapsed: Persistent.states.sidebar.notifications.collapsed
    implicitHeight: header.implicitHeight + 10

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
