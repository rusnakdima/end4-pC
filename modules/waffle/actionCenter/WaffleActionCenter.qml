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

        function onWaffleSidebarLeftOpenChanged() {
            if (GlobalStates.waffleSidebarLeftOpen)
                panelLoader.active = true;
        }
    }

    Loader {
        id: panelLoader
        active: GlobalStates.waffleSidebarLeftOpen
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:actionCenter"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                bottom: Config.options.waffles.bar.bottom
                top: !Config.options.waffles.bar.bottom
                right: true
            }

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            HyprlandFocusGrab {
                id: focusGrab
                active: true
                windows: [panelWindow]
                onCleared: content.close()
            }

            Connections {
                target: GlobalStates
                function onWaffleSidebarLeftOpenChanged() {
                    if (!GlobalStates.waffleSidebarLeftOpen)
                        content.close();
                }
            }

            ActionCenterContent {
                id: content
                anchors.fill: parent

                onClosed: {
                    GlobalStates.waffleSidebarLeftOpen = false;
                    panelLoader.active = false;
                }
            }
        }
    }

    function toggleOpen() {
        GlobalStates.waffleSidebarLeftOpen = !GlobalStates.waffleSidebarLeftOpen;
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle() {
            root.toggleOpen();
        }
    }

    // Namespaced alias so the waffle controls never address the end4-pC
    // sidebars, even when both families share the same shell.
    IpcHandler {
        target: "waffleSidebarLeft"

        function toggle() {
            root.toggleOpen();
        }
    }

    CompositorGlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: root.toggleOpen()
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.waffleSidebarLeftOpen = !GlobalStates.waffleSidebarLeftOpen;
        }
    }

    CompositorGlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.waffleSidebarLeftOpen = !GlobalStates.waffleSidebarLeftOpen;
        }
    }
}
