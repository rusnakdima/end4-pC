import QtQuick
import qs.modules.common
import qs.modules.waffle.looks

BarButton {
    id: root
    property string layoutName: "US"
    checked: false
    onClicked: { /* layout switch could go here */ }
    contentItem: WText {
        anchors.centerIn: parent
        text: root.layoutName
        font.pixelSize: 10
    }
    BarToolTip { text: "Keyboard Layout" }
}
