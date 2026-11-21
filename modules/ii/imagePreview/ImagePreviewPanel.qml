pragma ComponentBehavior: Bound

import qs
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * macOS Quick Look style image preview.
 * A frameless, screen-filling window with a dimmed backdrop and a large
 * centered card showing the image. All state and IPC logic lives in
 * services/ImagePreview; this file is only the view.
 */
Window {
    id: root
    title: "Image Preview"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    // Cover the whole screen so the backdrop dims the desktop behind the card.
    x: root.screen ? root.screen.geometry.x : 0
    y: root.screen ? root.screen.geometry.y : 0
    width: root.screen ? root.screen.geometry.width : 1280
    height: root.screen ? root.screen.geometry.height : 800

    readonly property int maxWidth: Config.options?.imagePreview?.maxWidth ?? 1280
    readonly property int maxHeight: Config.options?.imagePreview?.maxHeight ?? 900
    readonly property int imageWidth: Math.max(previewImage.sourceSize.width, 1)
    readonly property int imageHeight: Math.max(previewImage.sourceSize.height, 1)

    onClosing: event => ImagePreview.close()

    Connections {
        target: ImagePreview
        function onClosed() { root.hide(); }
        function onZoomChanged() { root.resizeToContent(); }
        function onFitModeChanged() { root.resizeToContent(); }
        function onImagePathChanged() { Qt.callLater(root.resizeToContent); }
    }

    Component.onCompleted: {
        root.show();
        Qt.callLater(root.resizeToContent);
        root.requestActivate();
        keyHandler.forceActiveFocus();
    }

    // Dimmed Quick Look backdrop. Clicking outside the card closes the preview.
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "#C0000000"
        MouseArea {
            anchors.fill: parent
            onClicked: ImagePreview.close()
        }
    }

    // Centered preview card, sized to the image (fit-to-screen by default).
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 640
        height: 480
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colUiPopupBackground
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        StyledRectangularShadow { target: card }

        ColumnLayout {
            anchors { fill: parent; margins: 10 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8

                MaterialSymbol {
                    text: "image"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: ImagePreview.sourceLabel || "Image Preview"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideMiddle
                }
                MaterialSymbol {
                    text: "fit_screen"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ImagePreview.resetZoom()
                    }
                }
                MaterialSymbol {
                    text: "zoom_in"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ImagePreview.zoomIn()
                    }
                }
                MaterialSymbol {
                    text: "zoom_out"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ImagePreview.zoomOut()
                    }
                }
                MaterialSymbol {
                    text: "close"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ImagePreview.close()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                clip: true

                Image {
                    id: previewImage
                    anchors.fill: parent
                    source: ImagePreview.imagePath
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    smooth: true
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: previewImage.status === Image.Error || ImagePreview.imagePath.length === 0
                    text: "Could not load image"
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    // Scale the card (not the window) to fit the image, macOS Quick Look style.
    function resizeToContent(): void {
        const scale = ImagePreview.fitMode
            ? Math.min((maxWidth - 48) / imageWidth, (maxHeight - 140) / imageHeight, 1)
            : ImagePreview.zoom;
        const w = Math.min(Math.max(Math.round(imageWidth * scale), 420), maxWidth);
        const h = Math.min(Math.max(Math.round(imageHeight * scale) + 110, 260), maxHeight);
        card.width = w;
        card.height = h;
    }

    Item {
        id: keyHandler
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                ImagePreview.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                ImagePreview.zoomIn();
                event.accepted = true;
            } else if (event.key === Qt.Key_Minus) {
                ImagePreview.zoomOut();
                event.accepted = true;
            } else if (event.key === Qt.Key_0) {
                ImagePreview.resetZoom();
                event.accepted = true;
            }
        }
    }
}
