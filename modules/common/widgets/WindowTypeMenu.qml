pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The window-type chooser opened by the fourth control.
 *
 * It is an Item, not a window: the overlay host is a full-screen layer
 * surface, so the menu can be positioned relative to the cluster and still
 * draw outside the cluster's bounds. That also keeps it on the same monitor
 * and the same z-order as the button that opened it.
 */
Item {
    id: root

    property string address: ""
    signal dismissed()

    readonly property string effectiveAddress: root.address || WindowControls.activeAddress
    readonly property var client: WindowControls.displayClient
    readonly property string currentType: WindowControls.displayType()

    implicitWidth: 208
    implicitHeight: menuBackground.implicitHeight

    Rectangle {
        id: menuBackground
        anchors.fill: parent
        implicitHeight: menuLayout.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainer
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 4
            radius: 12
            samples: 16
            color: "#80000000"
        }
    }

    ColumnLayout {
        id: menuLayout
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            text: Translation.tr("Window type")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.m3colors.m3onSurfaceVariant
        }

        Repeater {
            model: WindowControls.windowTypes

            delegate: RippleButton {
                id: typeButton
                required property string modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 36
                buttonRadius: Appearance.rounding.small
                padding: 6
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                toggled: typeButton.modelData === root.currentType
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover

                contentItem: RowLayout {
                    spacing: 8

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 18
                        text: WindowControls.typeSymbol(typeButton.modelData)
                        color: typeButton.toggled
                            ? Appearance.m3colors.m3onPrimary
                            : Appearance.m3colors.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr(WindowControls.typeLabel(typeButton.modelData))
                        color: typeButton.toggled
                            ? Appearance.m3colors.m3onPrimary
                            : Appearance.m3colors.m3onSurface
                    }

                    MaterialSymbol {
                        visible: typeButton.toggled
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 16
                        text: "check"
                        color: Appearance.m3colors.m3onPrimary
                    }
                }

                onClicked: {
                    WindowControls.setType(typeButton.modelData, root.effectiveAddress);
                    root.dismissed();
                }
            }
        }
    }
}
