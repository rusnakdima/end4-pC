pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Hyprland

MouseArea {
    id: root
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    property color contentColor: Appearance.colors.colOnLayer1
    property bool contentColorOverridden: false
    property bool vertical: Config.options.bar.vertical

    readonly property string layoutCode: KeyboardLayouts.currentLayoutCode
    readonly property string layoutName: KeyboardLayouts.currentLayoutName
    readonly property bool hasLayout: layoutCode.length > 0

    // Layout codes offered by the dropdown: the ones the compositor reports
    // for the main keyboard, falling back to the configured list.
    readonly property var layoutCodes: {
        const reported = (KeyboardLayouts.layoutNames ?? []).map(c => c.trim()).filter(c => c.length > 0);
        if (reported.length > 0) return reported;
        return (Config.options.hyprland.input.kbLayout ?? "")
            .split(",")
            .map(c => c.trim())
            .filter(c => c.length > 0);
    }

    implicitWidth: vertical
        ? Appearance.sizes.verticalBarWidth
        : (layoutText.implicitWidth + 8)
    implicitHeight: vertical
        ? (layoutText.implicitHeight + 6)
        : Appearance.sizes.barHeight

    visible: root.hasLayout

    // Switching the layout has to make the chosen code the active group, not
    // just reorder the list - HyprlandConfig.setKeyboardLayout does that.
    function applyLayout(code) {
        if (WM.compositor !== "hyprland") return;

        const applied = HyprlandConfig.setKeyboardLayout(code, root.layoutCodes);
        if (applied.length === 0) return;

        Config.options.hyprland.input.kbLayout = applied;
    }

    function toggleMenu() {
        menuLoader.active = !menuLoader.active;
    }

    function closeMenu() {
        menuLoader.active = false;
    }

    onClicked: root.toggleMenu()

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

    // The popup lives in its own file: a PopupWindow that is not the root of a
    // QML file never gets a surface, so the dropdown would stay invisible.
    Loader {
        id: menuLoader
        active: false
        sourceComponent: HyprlandXkbMenu {
            layoutCodes: root.layoutCodes
            activeCode: root.layoutCode

            anchor {
                window: root.QsWindow.window
                item: root
                gravity: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }

            onLayoutSelected: code => {
                root.applyLayout(code);
                root.closeMenu();
            }
            onMenuClosed: root.closeMenu()
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.containsMouse
        text: root.layoutName.length > 0 ? root.layoutName : root.layoutCode
    }
}
