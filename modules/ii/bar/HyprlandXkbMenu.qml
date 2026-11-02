pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell

PopupWindow {
    id: root

    // Emitted when the user picks a layout code.
    signal layoutSelected(code: string)
    // Emitted when the popup should close itself (dismissed by a click outside).
    signal menuClosed()

    property var layoutCodes: []
    property string activeCode: ""

    color: "transparent"
    implicitWidth: menuBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: menuBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    Component.onCompleted: {
        root.visible = true;
        GlobalFocusGrab.addDismissable(root);
    }
    Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

    Connections {
        target: GlobalFocusGrab
        function onDismissed() { root.menuClosed() }
    }

    Item {
        id: menuInputArea
        anchors.fill: menuBackground
    }

    StyledRectangularShadow {
        target: menuBackground
    }

    Rectangle {
        id: menuBackground
        WindowGlass {
            anchors.fill: parent
            glassEnabled: (parent?.color.a ?? 0) > 0
            cardRadius: parent?.radius ?? 0
            tint: parent?.color ?? 'transparent'
        }
        property real padding: 4

        anchors.centerIn: parent
        color: Appearance.colors.colUiPopupBackground
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        implicitWidth: menuColumn.implicitWidth + padding * 2
        implicitHeight: menuColumn.implicitHeight + padding * 2
        focus: true
        Keys.onEscapePressed: root.menuClosed()

        ColumnLayout {
            id: menuColumn
            anchors {
                fill: parent
                margins: parent.padding
            }
            spacing: 0

            Repeater {
                model: root.layoutCodes
                delegate: RippleButton {
                    id: layoutButton
                    required property var modelData
                    readonly property bool isActive: layoutButton.modelData.toLowerCase() === root.activeCode.toLowerCase()

                    Layout.fillWidth: true
                    implicitHeight: 34
                    implicitWidth: 180
                    buttonRadius: Appearance.rounding.small

                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "keyboard"
                            iconSize: Appearance.font.pixelSize.small
                            color: layoutButton.isActive
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: layoutButton.modelData.toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: layoutButton.isActive
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnSurface
                        }
                        Item { Layout.fillWidth: true }
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "check"
                            iconSize: Appearance.font.pixelSize.small
                            visible: layoutButton.isActive
                            color: Appearance.colors.colPrimary
                        }
                    }

                    onClicked: {
                        root.layoutSelected(layoutButton.modelData);
                        root.menuClosed();
                    }
                }
            }
        }
    }
}
