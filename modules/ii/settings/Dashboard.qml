import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    readonly property bool active: GlobalStates.settingsOpen && Config.options.settings.style === "dashboard"

    Loader {
        active: root.active

        sourceComponent: FloatingWindow {
            id: window
            title: "illogical-impulse Settings"
            color: Appearance.colors.colUiBackground

            WindowGlass {
                anchors.fill: parent
                tint: Appearance.colors.colUiBackground
            }

            implicitWidth: 1100
            implicitHeight: 680
            minimumSize: Qt.size(900, 600)

            // The dashboard is the other settings window: the capture
            // inhibitor has to be attached here too.
            Loader {
                active: WM.compositor === "hyprland"
                sourceComponent: ShortcutInhibitor {
                    window: window
                    enabled: GlobalStates.keybindCaptureArmed
                    onActiveChanged: GlobalStates.keybindCaptureInhibited = active
                }
            }

            property bool settled: false

            visible: true
            onVisibleChanged: {
                if (!visible) GlobalStates.settingsOpen = false;
            }
            onWidthChanged: settleTimer.restart()
            onHeightChanged: settleTimer.restart()

            Timer {
                id: settleTimer
                interval: 70
                running: true
                onTriggered: window.settled = true
            }

            Loader {
                anchors.fill: parent
                active: window.settled

                sourceComponent: DashboardContent {}
            }
        }
    }
}
