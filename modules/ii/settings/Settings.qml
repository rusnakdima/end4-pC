//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Scope {
    id: root

    readonly property real sizeScale: Config.options.settings.style === "minimal" ? 0.75 : 1.0
    property bool isMinimal: Config.options.settings.style === "minimal"

    Component.onCompleted: {
        GlobalStates.settingsOpen = false;
    }

    Dashboard {}

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.settingsOpen && Config.options.settings.style !== "dashboard"

        function hide() {
            GlobalStates.settingsOpen = false;
        }

        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        // Only the card is interactive. Without a mask the whole screen
        // sized surface would swallow every click, so nothing underneath
        // could be used while the panel is open.
        mask: Region {
            item: settingsWindow
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        onVisibleChanged: {
            if (visible) settingsWindow.userMoved = false;
        }

        Rectangle {
            id: settingsWindow
            width: Config.options.settings.style === "minimal" ? Math.min(parent.width - 70, 980 * sizeScale) : Math.min(parent.width - 80, 980 * sizeScale)
            height: Math.min(parent.height - 80, 665 * sizeScale)
            color: Appearance.colors.colUiBackground
            border.width: Config.options.settings.borderSize
            border.color: CF.ColorUtils.transparentize(Appearance.getColorFromName(Config.options.settings.borderColor), 0.8)
            radius: !isMinimal ? Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 5 : Appearance.rounding.screenRounding + 5
            z: 1

            property bool userMoved: false
            property real movedX: 0
            property real movedY: 0
            readonly property real centeredX: (parent.width - width) / 2
            readonly property real centeredY: (parent.height - height) / 2
            x: settingsWindow.userMoved ? settingsWindow.movedX : settingsWindow.centeredX
            y: settingsWindow.userMoved ? settingsWindow.movedY : settingsWindow.centeredY

            opacity: GlobalStates.settingsOpen ? 1 : 0
            scale: GlobalStates.settingsOpen ? 1 : 0.95

            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Keys.onTabPressed: (event) => {
            const count = settingsContent.pages.length;
            settingsContent.currentPage = (settingsContent.currentPage + 1) % count;
            settingsContent.showingProfile = false;
            event.accepted = true;
        }

        Keys.onBacktabPressed: (event) => {
            const count = settingsContent.pages.length;
            settingsContent.currentPage = (settingsContent.currentPage - 1 + count) % count;
            settingsContent.showingProfile = false;
            event.accepted = true;
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panelWindow.hide();
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                const instance = GlobalStates.currentPageInstance;
                if (instance && instance.contentY !== undefined) {
                    const step = 60;
                    const delta = event.key === Qt.Key_Down ? step : -step;
                    const maxY = Math.max(0, (instance.contentHeight ?? 0) - instance.height);
                    instance.contentY = Math.max(0, Math.min(maxY, instance.contentY + delta));
                }
                event.accepted = true;
                return;
            }
        }

            Rectangle {
                id: dragHandle
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 32
                color: "transparent"
                z: 2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    property real grabOffsetX: 0
                    property real grabOffsetY: 0

                    onPressed: (event) => {
                        const origin = settingsWindow.mapToItem(null, 0, 0);
                        grabOffsetX = event.scenePosition.x - origin.x;
                        grabOffsetY = event.scenePosition.y - origin.y;
                    }
                    onPositionChanged: (event) => {
                        if (!pressed) return;
                        const parentOrigin = settingsWindow.parent.mapToItem(null, 0, 0);
                        const newSceneX = event.scenePosition.x - grabOffsetX;
                        const newSceneY = event.scenePosition.y - grabOffsetY;
                        settingsWindow.movedX = Math.max(0, Math.min(settingsWindow.parent.width - settingsWindow.width, newSceneX - parentOrigin.x));
                        settingsWindow.movedY = Math.max(0, Math.min(settingsWindow.parent.height - settingsWindow.height, newSceneY - parentOrigin.y));
                        settingsWindow.userMoved = true;
                    }
                    onDoubleClicked: settingsWindow.userMoved = false
                }
            }

            RippleButton {
                id: closeButton
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 8
                    rightMargin: 12
                }
                // Above the drag handle, whose mouse area would swallow the click.
                z: 3

                onClicked: panelWindow.hide()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.title
                    text: "close"
                }
            }

            SettingsContent {
                id: settingsContent
                anchors.fill: parent
            }
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { GlobalStates.settingsOpen = !GlobalStates.settingsOpen; }
        function open(): void   { GlobalStates.settingsOpen = true; }
        function close(): void  { GlobalStates.settingsOpen = false; }
    }

    CompositorGlobalShortcut {
        name: "settingsToggle"
        description: "Toggles settings panel"
        onPressed: GlobalStates.settingsOpen = !GlobalStates.settingsOpen;
    }
}