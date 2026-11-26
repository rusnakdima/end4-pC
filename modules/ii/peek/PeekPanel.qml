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
 * Quick Look style preview for a file, image or selected text.
 * Frameless, screen-filling, with a dimmed backdrop and a centered card.
 * All state and IPC logic lives in services/Peek; this file is only the view.
 */
Window {
    id: root
    title: "Peek"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    x: root.screen ? root.screen.x : 0
    y: root.screen ? root.screen.y : 0
    width: root.screen ? root.screen.width : 1280
    height: root.screen ? root.screen.height : 800

    readonly property int previewWidth: Math.round(root.width * 0.75)
    readonly property int previewHeight: Math.round(root.height * 0.75)

    onClosing: event => Peek.close()

    Connections {
        target: Peek
        function onClosed(): void { root.hide(); }
        function onZoomChanged(): void { root.resizeToContent(); }
        function onFitModeChanged(): void { root.resizeToContent(); }
        function onSourcePathChanged(): void { Qt.callLater(root.resizeToContent); }
        function onKindChanged(): void { Qt.callLater(root.resizeToContent); }
    }

    Component.onCompleted: {
        root.show();
        Qt.callLater(root.resizeToContent);
        root.requestActivate();
        keyHandler.forceActiveFocus();
    }

    // Dims the desktop; clicking outside the card closes the preview.
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Appearance.colors.colScrim
        MouseArea {
            anchors.fill: parent
            onClicked: Peek.close()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: previewWidth
        height: previewHeight
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
                    text: Peek.kind === "image" ? "image" : "description"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Peek.displayLabel || "Peek"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideMiddle
                }
                StyledText {
                    text: Peek.kind
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
                MaterialSymbol {
                    visible: Peek.kind === "image"
                    text: "fit_screen"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Peek.resetZoom()
                    }
                }
                MaterialSymbol {
                    visible: Peek.kind === "image"
                    text: "zoom_in"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Peek.zoomIn()
                    }
                }
                MaterialSymbol {
                    visible: Peek.kind === "image"
                    text: "zoom_out"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Peek.zoomOut()
                    }
                }
                MaterialSymbol {
                    text: "edit"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Peek.edit()
                    }
                }
                MaterialSymbol {
                    text: "close"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Peek.close()
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
                    visible: Peek.kind === "image"
                    source: Peek.sourcePath
                    fillMode: Image.PreserveAspectFit
                    scale: Peek.fitMode ? 1 : Peek.zoom
                    asynchronous: true
                    cache: false
                    smooth: true
                }

                Flickable {
                    id: textArea
                    anchors.fill: parent
                    visible: Peek.kind === "text" || Peek.kind === "binary"
                    contentWidth: textContent.width
                    contentHeight: textContent.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        id: textContent
                        width: textArea.width
                        text: Peek.content
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.WrapAnywhere
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: Peek.kind === "empty"
                    text: "Nothing selected"
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: Peek.kind === "notfound"
                    text: "File not found — press E to open in nvim"
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    // Images fill 75% of the screen; other targets keep a readable fixed size.
    function resizeToContent(): void {
        if (Peek.kind !== "image") {
            card.width = Math.min(760, Math.max(420, root.width - 80));
            card.height = Math.min(540, Math.max(280, root.height - 120));
            return;
        }
        card.width = previewWidth;
        card.height = previewHeight;
    }

    Item {
        id: keyHandler
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Peek.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_E) {
                Peek.edit();
                event.accepted = true;
            } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                Peek.zoomIn();
                event.accepted = true;
            } else if (event.key === Qt.Key_Minus) {
                Peek.zoomOut();
                event.accepted = true;
            } else if (event.key === Qt.Key_0) {
                Peek.resetZoom();
                event.accepted = true;
            }
        }
    }
}
