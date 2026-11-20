pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.services

/** Animated rings at the pointer, triggered by DesktopUtilities.findMouse(). */
Scope {
    id: root

    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: overlayLoader
            required property var modelData
            active: DesktopUtilities.findMouseActive
            sourceComponent: PanelWindow {
                id: window
                screen: overlayLoader.modelData

                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                WlrLayershell.namespace: "quickshell:findMouse"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                mask: Region { item: null }

                Repeater {
                    model: DesktopUtilities.cursorSamples
                    delegate: Item {
                        required property var modelData
                        required property int index

                        property real localX: modelData.x - (window.screen?.x ?? 0)
                        property real localY: modelData.y - (window.screen?.y ?? 0)
                        property bool onThisScreen: localX >= 0 && localY >= 0
                            && localX <= window.width && localY <= window.height

                        visible: onThisScreen
                        x: localX - 26
                        y: localY - 26
                        width: 52
                        height: 52

                        Rectangle {
                            anchors.centerIn: parent
                            width: 34 + index * 2
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 3
                            border.color: Appearance.colors.colPrimary
                            opacity: Math.max(0, 1 - index * 0.14)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10
                            height: 10
                            radius: 5
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }
}
