import QtQuick
import QtQuick.Controls
import qs.modules.common

/** A Flickable with standard styling and touchpad sensitivity. */
Flickable {
    id: root
    readonly property bool touchpadScrolling: touchpadScroll.scrolling
    // Rail-style lists that overflow can show their scrollbar permanently:
    // there is no other hint that more entries exist below the fold.
    property bool alwaysShowVerticalScrollBar: false

    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    ScrollBar.vertical: StyledScrollBar {
        policy: root.alwaysShowVerticalScrollBar && root.contentHeight > root.height
            ? ScrollBar.AlwaysOn
            : ScrollBar.AsNeeded
    }

    TouchpadScrollArea {
        id: touchpadScroll
        flickable: root
    }
}
