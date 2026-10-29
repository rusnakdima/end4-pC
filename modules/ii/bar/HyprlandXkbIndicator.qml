import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MouseArea {
    id: root
    acceptedButtons: Qt.NoButton
    hoverEnabled: true

    property color contentColor: Appearance.colors.colOnLayer1
    property bool contentColorOverridden: false
    property bool vertical: Config.options.bar.vertical

    readonly property string layoutCode: KeyboardLayouts.currentLayoutCode
    readonly property string layoutName: KeyboardLayouts.currentLayoutName
    readonly property bool hasLayout: layoutCode.length > 0

    implicitWidth: vertical
        ? Appearance.sizes.verticalBarWidth
        : (layoutText.implicitWidth + 8)
    implicitHeight: vertical
        ? (layoutText.implicitHeight + 6)
        : Appearance.sizes.barHeight

    visible: root.hasLayout

    StyledText {
        id: layoutText
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.layoutCode
        font.pixelSize: root.vertical
            ? Appearance.font.pixelSize.smaller
            : Appearance.font.pixelSize.small
        color: root.contentColorOverridden
            ? root.contentColor
            : Appearance.colors.colOnLayer1
        animateChange: true
    }

    StyledToolTip {
        text: root.layoutName.length > 0 ? root.layoutName : root.layoutCode
    }
}
