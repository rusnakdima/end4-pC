//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    readonly property real sizeScale: Config.options.settings.style === "minimal" ? 0.75 : 1.0
    property bool isMinimal: Config.options.settings.style === "minimal"

    Component.onCompleted: {
        GlobalStates.settingsOpen = false;
    }

    Dashboard {}

    // Settings is a plain window, not a layer surface. Hyprland floats it by
    // title (dots/.config/hypr/hyprland/rules.lua matches
    // "^(illogical-impulse Settings)$") and owns its geometry from then on:
    // SUPER+left/right drags it, SUPER+middle and the window border resize it.
    // Nothing in this file moves or sizes the window -- that is the point, and
    // it is how upstream's settings app works. It also means there is no
    // fullscreen backdrop: clicking away leaves the window open, like any app.
    Loader {
        active: GlobalStates.settingsOpen && Config.options.settings.style !== "dashboard"

        sourceComponent: FloatingWindow {
            id: window
            title: "illogical-impulse Settings"
            color: Appearance.colors.colUiBackground

            WindowGlass {
                anchors.fill: parent
                tint: Appearance.colors.colUiBackground
            }

            implicitWidth: 980 * sizeScale
            implicitHeight: 665 * sizeScale
            minimumSize: Qt.size(480, 320)

            property bool settled: false

            visible: true
            onVisibleChanged: {
                // Covers the window being closed from outside this file
                // (killactive, an Alt-Tab dismissal), so the shell's own
                // state never claims Settings is open when it is not.
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

            // The key handlers live on an Item, because a Window is not one,
            // and on an ancestor of the content so an unaccepted Escape still
            // bubbles up to them from the search field.
            Item {
                id: keyScope
                anchors.fill: parent
                focus: true

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.settingsOpen = false;
                        event.accepted = true;
                        return;
                    }

                    if (event.key === Qt.Key_Super || event.key === Qt.Key_Meta) {
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

                Keys.onTabPressed: (event) => {
                    const pages = contentLoader.item?.pages ?? [];
                    if (pages.length > 0) {
                        const item = contentLoader.item;
                        item.currentPage = (item.currentPage + 1) % pages.length;
                        item.showingProfile = false;
                    }
                    event.accepted = true;
                }

                Keys.onBacktabPressed: (event) => {
                    const pages = contentLoader.item?.pages ?? [];
                    if (pages.length > 0) {
                        const item = contentLoader.item;
                        item.currentPage = (item.currentPage - 1 + pages.length) % pages.length;
                        item.showingProfile = false;
                    }
                    event.accepted = true;
                }

                // Created once the window has a real size, the same way
                // Dashboard.qml does it: a QQuickWindow reports 0x0 until its
                // platform window exists, and laying the pages out against
                // that wastes a full relayout of every page.
                Loader {
                    id: contentLoader
                    anchors.fill: parent
                    active: window.settled

                    sourceComponent: SettingsContent {}
                }
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
