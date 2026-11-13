import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    default property list<Item> items
    property real bigRadius: Appearance.rounding.normal
    property real smallRadius: Appearance.rounding.unsharpenmore
    property color bgcolor: Appearance.colors.colLayer1
    property real itemVerticalPadding: 24
    property bool glass: false
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight

    // A child that hides itself leaves no row behind: the row collapses to
    // zero height and stops painting, so a hidden control no longer leaves an
    // empty band. The row itself is deliberately never hidden: Item.visible
    // is inherited, so hiding the row would hide the child too, and the row
    // could then never come back when the child becomes visible again.
    readonly property int firstShownIndex: {
        for (let i = 0; i < items.length; i++)
            if (items[i] && items[i].visible !== false) return i;
        return -1;
    }
    readonly property int lastShownIndex: {
        for (let i = items.length - 1; i >= 0; i--)
            if (items[i] && items[i].visible !== false) return i;
        return -1;
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: root.items.length
            delegate: Rectangle {
                required property int index
                readonly property bool rowHidden: root.items[index]?.visible === false
                readonly property bool isFirst: index === root.firstShownIndex
                readonly property bool isLast: index === root.lastShownIndex
                Layout.fillWidth: true
                implicitHeight: rowHidden
                    ? 0
                    : (root.items[index]?.implicitHeight ?? 0) + root.itemVerticalPadding
                color: rowHidden ? "transparent" : root.bgcolor

                WindowGlass {
                    anchors.fill: parent
                    visible: !rowHidden
                    glassEnabled: root?.glass ?? false
                    topLeftRadius: parent.topLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    bottomRightRadius: parent.bottomRightRadius
                    tint: root?.bgcolor ?? "transparent"
                }
                topLeftRadius:     isFirst ? root.bigRadius : root.smallRadius
                topRightRadius:    isFirst ? root.bigRadius : root.smallRadius
                bottomLeftRadius:  isLast  ? root.bigRadius : root.smallRadius
                bottomRightRadius: isLast  ? root.bigRadius : root.smallRadius

                Component.onCompleted: {
                    const child = root.items[index]
                    if (child) {
                        child.parent = contentArea
                        child.Layout.fillWidth = true
                    }
                }

                ColumnLayout {
                    id: contentArea
                    anchors { fill: parent; margins: 8 }
                    spacing: 0
                }
            }
        }
    }
}
