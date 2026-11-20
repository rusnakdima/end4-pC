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
 * Frameless Material 3 window showing the current image. All logic lives in
 * services/ImagePreview; this is only the view.
 */
Window {
    id: root

    title: "Image Preview"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    readonly property int maxWidth: Config.options?.imagePreview?.maxWidth ?? 960
    readonly property int maxHeight: Config.options?.imagePreview?.maxHeight ?? 720
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
        Qt.callLater(() => {
            root.resizeToContent();
            root.placeCentered();
        });
        root.requestActivate();
        keyHandler.forceActiveFocus();
    }

    function resizeToContent(): void {
        const scale = ImagePreview.fitMode
            ? Math.min((maxWidth - 32) / imageWidth, (maxHeight - 144) / imageHeight, 1)
            : ImagePreview.zoom;
        const w = Math.min(Math.max(Math.round(imageWidth * scale), 360), maxWidth);
        const h = Math.min(Math.max(Math.round(imageHeight * scale) + 112, 220), maxHeight);
        root.width = w;
        root.height = h;
    }

    function placeCentered(): void {
        const geometry = root.screen?.geometry;
        if (!geometry) return;
        root.x = geometry.x + Math.round((geometry.width - root.width) / 2);
        root.y = geometry.y + Math.round((geometry.height - root.height) / 2);
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

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colUiPopupBackground
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        StyledRectangularShadow { target: card }

        ColumnLayout {
            anchors { fill: parent; margins: 8 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
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
                MouseArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cursorShape: Qt.SizeAllCursor
                    onPressed: root.startSystemMove()
                }
                MaterialSymbol {
                    text: "fit_screen"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ImagePreview.resetZoom()
                    }
                }
                MaterialSymbol {
                    text: "zoom_in"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ImagePreview.zoomIn()
                    }
                }
                MaterialSymbol {
                    text: "zoom_out"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ImagePreview.zoomOut()
                    }
                }
                MaterialSymbol {
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
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
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }
        }
    }
}
