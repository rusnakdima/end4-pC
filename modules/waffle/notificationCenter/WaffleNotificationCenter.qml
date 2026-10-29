import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    Connections {
        target: GlobalStates

        function onWaffleSidebarRightOpenChanged() {
            if (GlobalStates.waffleSidebarRightOpen) panelLoader.active = true;
        }
    }

    Loader {
        id: panelLoader
        active: GlobalStates.waffleSidebarRightOpen
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wNotificationCenter"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                bottom: true
                top: true
                right: true
            }

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            HyprlandFocusGrab {
                id: focusGrab
                active: true
                windows: [panelWindow]
                onCleared: content.close();
            }

            Connections {
                target: GlobalStates
                function onWaffleSidebarRightOpenChanged() {
                    if (!GlobalStates.waffleSidebarRightOpen) content.close();
                }
            }

            NotificationCenterContent {
                id: content
                anchors.fill: parent

                onClosed: {
                    GlobalStates.waffleSidebarRightOpen = false;
                    panelLoader.active = false;
                }
            }
        }
    }

    function toggleOpen() {
        GlobalStates.waffleSidebarRightOpen = !GlobalStates.waffleSidebarRightOpen;
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle() {
            root.toggleOpen();
        }
    }

    // Namespaced alias so the waffle controls never address the end4-pC
    // sidebars, even when both families share the same shell.
    IpcHandler {
        target: "waffleSidebarRight"

        function toggle() {
            root.toggleOpen();
        }
    }

    CompositorGlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles notification center on press"

        onPressed: root.toggleOpen();
    }
}
