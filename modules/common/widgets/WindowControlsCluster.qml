pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The four-button control cluster, shared by the floating overlay and the
 * bar fallback. All behaviour lives in the WindowControls service; this file
 * only decides which buttons exist and how they look.
 *
 * The first three buttons follow Windows semantics and ordering. The fourth
 * opens the type chooser in the overlay, or cycles the type in the compact
 * bar variant where a flyout would not fit.
 */
Item {
    id: root

    property string address: ""
    property bool compact: false
    property string reveal: "hover"
    property bool useMenu: true
    // When embedded in a titlebar strip, the pill background is redundant.
    property bool embedded: false
    property var buttons: Config.options?.windows?.controls?.buttons
        ?? ["minimize", "maximize", "close", "type"]

    property alias menuOpen: typeMenuLoader.active
    readonly property string effectiveAddress: root.address || WindowControls.activeAddress
    readonly property var client: WindowControls.displayClient
    readonly property string currentType: WindowControls.displayType()
    readonly property int buttonSize: root.compact
        ? Math.max(24, (Config.options?.windows?.controls?.buttonSize ?? 36) - 8)
        : (Config.options?.windows?.controls?.buttonSize ?? 36)
    readonly property int iconSize: Math.round(root.buttonSize * 0.55)

    implicitWidth: buttonRow.implicitWidth + 8
    implicitHeight: root.buttonSize + 8

    HoverHandler {
        id: hoverHandler
        target: root
    }

    Rectangle {
        id: clusterBackground
        anchors.fill: parent
        radius: Appearance.rounding.large
        visible: !root.embedded
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        opacity: root.reveal === "always" || hoverHandler.hovered || typeMenuLoader.active ? 1 : 0.82

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    Row {
        id: buttonRow
        anchors.centerIn: parent
        spacing: 2

        component ControlButton: RippleButton {
            id: controlButton
            required property string symbol
            required property string tip
            property bool danger: false

            implicitWidth: root.buttonSize
            implicitHeight: root.buttonSize
            buttonRadius: Appearance.rounding.full
            padding: 0
            colBackground: "transparent"
            colBackgroundHover: controlButton.danger
                ? Appearance.colors.colError
                : Appearance.colors.colLayer1Hover

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                iconSize: root.iconSize
                text: controlButton.symbol
                color: controlButton.danger
                    ? Appearance.colors.colOnError
                    : Appearance.m3colors.m3onSurface
            }

            StyledToolTip {
                text: controlButton.tip
            }
        }

        ControlButton {
            visible: WindowControls.showsButton(root.buttons,"minimize")
            enabled: WindowControls.displayCanMinimize()
            symbol: "minimize"
            tip: Translation.tr("Minimize")
            onClicked: WindowControls.minimize(root.effectiveAddress)
        }

        ControlButton {
            visible: WindowControls.showsButton(root.buttons,"maximize")
            enabled: WindowControls.displayCanMaximize()
            symbol: WindowControls.windowStateSymbol(root.client?.fullscreen ?? 0)
            tip: Number(root.client?.fullscreen ?? 0) === 0 ? Translation.tr("Maximize") : Translation.tr("Restore")
            onClicked: WindowControls.maximize(root.effectiveAddress)
        }

        ControlButton {
            visible: WindowControls.showsButton(root.buttons,"close")
            danger: true
            symbol: "close"
            tip: Translation.tr("Close")
            onClicked: WindowControls.close(root.effectiveAddress)
        }

        Rectangle {
            visible: WindowControls.showsButton(root.buttons,"type") && (WindowControls.showsButton(root.buttons,"minimize") || WindowControls.showsButton(root.buttons,"maximize") || WindowControls.showsButton(root.buttons,"close"))
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Math.round(root.buttonSize * 0.5)
            color: Appearance.colors.colOutlineVariant
        }

        ControlButton {
            id: typeButton
            visible: WindowControls.showsButton(root.buttons,"type")
            symbol: "layers"
            tip: root.useMenu ? Translation.tr("Window type") : (Translation.tr("Window type") + ": " + root.currentType)
            toggled: root.useMenu && typeMenuLoader.active
            colBackgroundToggled: Appearance.colors.colPrimary
            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
            colRippleToggled: Appearance.colors.colPrimaryActive

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                iconSize: root.iconSize
                text: "layers"
                color: typeButton.toggled
                    ? Appearance.m3colors.m3onPrimary
                    : Appearance.m3colors.m3onSurface
            }

            onClicked: {
                if (root.useMenu) typeMenuLoader.active = !typeMenuLoader.active;
                else WindowControls.cycleType(root.effectiveAddress);
            }
        }
    }

    // The flyout lives in the same window as the cluster so it stays on the
    // correct monitor and z-order. The compact bar variant never loads it.
    Loader {
        id: typeMenuLoader
        active: false
        anchors {
            top: root.bottom
            right: root.right
            topMargin: 6
        }
        z: 10
        sourceComponent: WindowTypeMenu {
            address: root.effectiveAddress
            onDismissed: typeMenuLoader.active = false
        }
    }
}
