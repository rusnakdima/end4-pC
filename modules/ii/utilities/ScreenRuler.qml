pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/** A draggable, resizable on-screen ruler measuring pixels and centimetres. */
Scope {
    id: root

    Loader {
        active: DesktopUtilities.rulerActive
        sourceComponent: PanelWindow {
            id: window
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:screenRuler"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: DesktopUtilities.rulerActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region { item: ruler }

            property real rulerLength: 320
            property real rulerThickness: 58

            Item {
                id: keyHandler
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        DesktopUtilities.toggleRuler();
                        event.accepted = true;
                    }
                }
            }
            Component.onCompleted: keyHandler.forceActiveFocus()

            MouseArea {
                anchors.fill: parent
                onClicked: DesktopUtilities.toggleRuler()
            }

            Rectangle {
                id: ruler
                width: window.rulerLength
                height: window.rulerThickness
                x: Math.max(8, (window.width - width) / 2)
                y: Math.max(8, (window.height - height) / 2)
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                // Drag the whole ruler.
                MouseArea {
                    id: dragArea
                    anchors {
                        fill: parent
                        rightMargin: 14
                    }
                    cursorShape: Qt.SizeAllCursor
                    property real lastX: 0
                    property real lastY: 0
                    onPressed: mouse => {
                        lastX = mouse.x;
                        lastY = mouse.y;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        ruler.x = Math.min(Math.max(0, ruler.x + mouse.x - lastX), window.width - ruler.width);
                        ruler.y = Math.min(Math.max(0, ruler.y + mouse.y - lastY), window.height - ruler.height);
                    }
                }

                // Tick marks every 10 px, labelled every 100 px.
                Repeater {
                    model: Math.floor(window.rulerLength / 10)
                    delegate: Rectangle {
                        required property int index
                        x: (index + 1) * 10
                        y: 4
                        width: 1
                        height: (index + 1) % 10 === 0 ? 14 : 7
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: (index + 1) % 10 === 0 ? 0.9 : 0.45
                    }
                }
                Repeater {
                    model: Math.floor(window.rulerLength / 100)
                    delegate: StyledText {
                        required property int index
                        x: (index + 1) * 100 - 12
                        y: 20
                        text: `${(index + 1) * 100}`
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }

                // Resize handle on the right edge.
                Rectangle {
                    width: 14
                    height: parent.height
                    anchors.right: parent.right
                    color: Appearance.colors.colPrimaryContainer
                    opacity: resizeArea.pressed ? 0.9 : 0.35
                    MouseArea {
                        id: resizeArea
                        anchors.fill: parent
                        cursorShape: Qt.SizeHorCursor
                        property real startX: 0
                        property real startLength: 0
                        onPressed: mouse => {
                            startX = mouse.x;
                            startLength = window.rulerLength;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return;
                            window.rulerLength = Math.min(1200, Math.max(60, startLength + mouse.x - startX));
                        }
                    }
                }
            }

            // Live measurement readout, pinned above the ruler.
            Rectangle {
                x: ruler.x
                y: Math.max(0, ruler.y - 30)
                implicitWidth: readout.implicitWidth + 16
                implicitHeight: 24
                radius: 12
                color: Appearance.colors.colSecondaryContainer
                StyledText {
                    id: readout
                    anchors.centerIn: parent
                    text: `${Math.round(window.rulerLength)} px · ${(window.rulerLength / 96 * 2.54).toFixed(1)} cm`
                    color: Appearance.colors.colOnSecondaryContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }
}
