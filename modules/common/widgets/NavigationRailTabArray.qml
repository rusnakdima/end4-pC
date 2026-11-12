import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int currentIndex: 0
    property bool expanded: false
    property color colToggled: Appearance.colors.colSecondaryContainer
    default property alias data: tabBarColumn.data
    implicitHeight: tabBarColumn.implicitHeight
    implicitWidth: tabBarColumn.implicitWidth
    Layout.topMargin: Config.options.settings.sidebarDensity === "compact" ? 12 : 25

    // The tabs are the part of the rail that grows with the number of pages,
    // so they are the part that has to scroll when the settings window is
    // short -- the rail itself is anchored top/bottom and used to just push
    // them past the bottom of the card, unreachable. The highlight lives
    // inside the flickable as well, otherwise it stops tracking the tabs as
    // soon as they move.
    StyledFlickable {
        id: railScroll
        anchors.fill: parent
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: tabBarColumn.implicitHeight
        contentWidth: width
        alwaysShowVerticalScrollBar: true

        Rectangle {
            property real itemHeight: tabBarColumn.children[0]?.baseSize ?? 56
            property real baseHighlightHeight: tabBarColumn.children[0]?.baseHighlightHeight ?? 56
            anchors {
                top: tabBarColumn.top
                left: tabBarColumn.left
                topMargin: itemHeight * root.currentIndex + (root.expanded ? 0 : ((itemHeight - baseHighlightHeight) / 2))
            }
            radius: Config.options.settings.style === "minimal" ? Appearance.rounding.small : Appearance.rounding.full
            color: root.colToggled
            implicitHeight: root.expanded ? itemHeight : baseHighlightHeight
            implicitWidth: tabBarColumn?.children[root.currentIndex]?.visualWidth ?? 100

            Behavior on anchors.topMargin {
                NumberAnimation {
                    duration: Appearance.animationCurves.expressiveFastSpatialDuration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                }
            }
        }

        ColumnLayout {
            id: tabBarColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            spacing: 0
        }
    }
}
