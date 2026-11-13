pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import Quickshell.Wayland

/**
 * One live window preview in the Alt+Tab deck.
 *
 * The card is the same visual unit as the overview's window tiles: a live
 * ScreencopyView, clipped to a rounded surface, with the app icon underneath as
 * the fallback when the compositor cannot capture the toplevel yet.
 */
Item {
    id: root

    required property var entry
    property bool selected: false
    property real cardWidth: 400
    property real cardHeight: 250
    property string workspaceBadge: ""

    signal requestActivate()

    readonly property var windowData: root.entry ? root.entry.windowData : null
    readonly property string iconPath: SystemAppearance.iconPath(AppSearch.guessIcon(root.windowData?.class), "")
    readonly property bool dark: Appearance.m3colors.darkmode

    width: cardWidth
    height: cardHeight

    StyledRectangularShadow {
        target: surface
        visible: root.selected
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Appearance.rounding.normal + 3 // 20 px, Mandara card radius
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: root.selected ? 2 : 1
        border.color: root.selected
            ? Appearance.colors.colPrimary
            : ColorUtils.applyAlpha(Appearance.colors.colOutlineVariant, root.dark ? 0.45 : 0.65)
    }

    // A hairline outside the card, only for the selection. It reads as a glow
    // without tinting the preview itself.
    Rectangle {
        id: selectionRing
        anchors.fill: surface
        anchors.margins: -5
        radius: surface.radius + 5
        color: "transparent"
        border.width: 2
        border.color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.32)
        visible: root.selected
    }

    Item {
        id: previewClip
        anchors.fill: parent
        anchors.margins: 3
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: previewClip.width
                height: previewClip.height
                radius: surface.radius - 3
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.m3colors.m3surfaceContainerHighest
        }

        // Fallback shown only while there is no capture to display.
        MaterialSymbol {
            anchors.centerIn: parent
            text: "web_asset"
            iconSize: 54
            color: ColorUtils.applyAlpha(Appearance.colors.colOnSurfaceVariant, 0.45)
            visible: !preview.hasContent
        }

        Image {
            id: appIcon
            anchors.centerIn: parent
            width: 54
            height: 54
            source: root.iconPath
            sourceSize: Qt.size(54, 54)
            fillMode: Image.PreserveAspectFit
            visible: source !== "" && status === Image.Ready && !preview.hasContent
        }

        ScreencopyView {
            id: preview
            // Cover the card: the window keeps its own aspect ratio and the
            // tiny overflow is clipped by the rounded mask above.
            readonly property real winAspect: {
                const s = root.windowData?.size;
                return (s && s[0] > 0 && s[1] > 0) ? (s[0] / s[1]) : 1.6;
            }
            readonly property real fitWidth: Math.max(previewClip.width, previewClip.height * winAspect)
            width: fitWidth
            height: fitWidth / winAspect
            anchors.centerIn: parent
            captureSource: root.visible && root.entry && root.entry.toplevel ? root.entry.toplevel : null
            live: root.visible
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.applyAlpha(
                Appearance.colors.colScrim,
                root.selected ? 0.02 : (Appearance.m3colors.darkmode ? 0.10 : 0.05))
        }
    }

    // Shown only when the deck has widened beyond the focused workspace, so
    // the user can see which workspace a card will switch to.
    Rectangle {
        id: workspaceBadgePill
        visible: root.workspaceBadge !== ""
        anchors {
            top: parent.top
            right: parent.right
            margins: 10
        }
        implicitWidth: Math.min(workspaceBadgeLabel.implicitWidth + 14, 150)
        implicitHeight: 20
        radius: 10
        color: ColorUtils.applyAlpha(Appearance.colors.colScrim, 0.62)
        border.width: 1
        border.color: ColorUtils.applyAlpha("#ffffff", 0.18)

        StyledText {
            id: workspaceBadgeLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, workspaceBadgePill.width - 14)
            text: root.workspaceBadge
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 11
            color: "#ffffff"
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.requestActivate()
    }
}
