import QtQuick
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

BarButton {
    id: root

    // User-editable list of XKB layout codes the dropdown offers, in the order
    // the user wants them listed.
    readonly property var layoutCodes: (Config.options.waffles.bar.keyboardLayouts ?? "")
        .split(",")
        .map(s => s.trim())
        .filter(s => s.length > 0)

    // Active layout code, falling back to the first configured one.
    readonly property string activeCode: {
        const current = (KeyboardLayouts.currentLayoutCode ?? "").trim();
        if (current.length > 0) return current;
        return root.layoutCodes.length > 0 ? root.layoutCodes[0] : "";
    }

    // Hyprland treats the first entry of kb_layout as the active group, so the
    // chosen layout has to come first.
    function applyLayout(code) {
        if (WM.compositor !== "hyprland") return;

        const target = code.trim();
        if (target.length === 0) return;

        const others = root.layoutCodes.filter(c => c.toLowerCase() !== target.toLowerCase());
        const applied = [target, ...others].join(",");

        HyprlandConfig.set("input:kb_layout", applied);
        Config.options.hyprland.input.kbLayout = applied;
    }

    onClicked: {
        if (WM.compositor !== "hyprland") return;
        layoutMenu.active = true;
    }

    contentItem: Item {
        implicitHeight: layoutText.implicitHeight
        implicitWidth: layoutText.implicitWidth

        WText {
            id: layoutText
            anchors.centerIn: parent
            text: root.activeCode.toUpperCase()
            font.pixelSize: 10
        }
    }

    BarMenu {
        id: layoutMenu

        model: root.layoutCodes.map(code => ({
            iconName: code.toLowerCase() === root.activeCode.toLowerCase() ? "checkmark" : "keyboard",
            text: code.toUpperCase(),
            action: () => root.applyLayout(code)
        }))
    }

    BarToolTip {
        text: `${Translation.tr("Keyboard Layout")}: ${root.activeCode.toUpperCase()}`
        extraVisibleCondition: root.shouldShowTooltip
    }
}
