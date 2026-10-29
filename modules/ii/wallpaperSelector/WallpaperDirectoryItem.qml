import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs
import Quickshell.Widgets

Item {
    id: root

    required property var fileModelData
    property bool isDirectory: fileModelData ? Boolean(fileModelData.fileIsDir) : false
    readonly property bool isVideoSource: fileModelData ? Images.isVideoPath(fileModelData.fileName) : false
    property bool useThumbnail: fileModelData ? (!root.isDirectory && Images.isValidImageByName(fileModelData.fileName)) : false
    // The colors of the cell. The shell theme provides the defaults, the
    // grid overrides them for the selected and the hovered cells.
    property color colBackground: Appearance.colors.colLayer1
    property color colText: Appearance.colors.colOnLayer1
    property alias radius: background.radius
    property alias margins: background.anchors.margins
    property bool showLabel: true
    property alias padding: wallpaperItemColumnLayout.anchors.margins
    readonly property real imageWidth: Math.max(1, root.width - 2 * (root.margins + root.padding))
    readonly property real imageHeight: Math.max(1, root.height - 2 * (root.margins + root.padding)
        - (root.showLabel ? wallpaperItemColumnLayout.spacing + wallpaperItemName.implicitHeight : 0))
    // The size of a folder icon. A fixed size like the icon view of a file
    // manager shows, but never bigger than the picture area of the cell.
    readonly property real folderIconSize: Math.min(64, Math.min(root.imageWidth, root.imageHeight))
    // The aspect ratio of the thumbnail. It is only known once the thumbnail
    // has been loaded, until then the picture fills the whole area.
    readonly property real thumbnailAspectRatio: (thumbnailImage.status === Image.Ready && thumbnailImage.implicitHeight > 0)
        ? thumbnailImage.implicitWidth / thumbnailImage.implicitHeight
        : 0
    // The size of the thumbnail. Like a file manager, the picture keeps its
    // aspect ratio and is centered in the picture area of the cell, so the
    // surface of the cell is visible around it.
    readonly property real thumbnailFrameWidth: root.thumbnailAspectRatio > 0
        ? Math.min(root.imageWidth, root.imageHeight * root.thumbnailAspectRatio)
        : root.imageWidth
    readonly property real thumbnailFrameHeight: root.thumbnailAspectRatio > 0
        ? root.thumbnailFrameWidth / root.thumbnailAspectRatio
        : root.imageHeight

    signal activated()
    signal previewRequested()

    margins: Appearance.sizes.wallpaperSelectorItemMargins
    padding: Appearance.sizes.wallpaperSelectorItemPadding

    Rectangle {
        id: background

        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: root.colBackground

        ColumnLayout {
            id: wallpaperItemColumnLayout

            anchors.fill: parent
            spacing: 4

            Item {
                id: wallpaperItemImageContainer

                Layout.fillHeight: true
                Layout.fillWidth: true

                // The thumbnail of an image or a video. Like the icon view of
                // a file manager, the picture keeps its aspect ratio and is
                // centered in the picture area of the cell, so the surface of
                // the cell stays visible around it. The picture itself keeps
                // the rounded corners of the shell and gets a shadow.
                StyledRectangularShadow {
                    target: thumbnailFrame
                    visible: root.useThumbnail && thumbnailImage.status === Image.Ready
                }

                ClippingRectangle {
                    id: thumbnailFrame

                    anchors.centerIn: parent
                    width: root.thumbnailFrameWidth
                    height: root.thumbnailFrameHeight
                    radius: Appearance.rounding.small
                    color: "transparent"
                    visible: root.useThumbnail && root.width > 0 && root.height > 0

                    ThumbnailImage {
                        id: thumbnailImage
                        anchors.fill: parent
                        generateThumbnail: true
                        sourcePath: (fileModelData && fileModelData.filePath) ? fileModelData.filePath : ""
                        cache: false
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: root.imageWidth
                        sourceSize.height: root.imageHeight

                        Connections {
                            function onThumbnailGenerated(directory) {
                                if (thumbnailImage.status !== Image.Error)
                                    return ;

                                if (FileUtils.parentDirectory(thumbnailImage.sourcePath) !== FileUtils.trimFileProtocol(directory))
                                    return ;

                                thumbnailImage.reload();
                            }

                            function onThumbnailGeneratedFile(filePath) {
                                if (thumbnailImage.status !== Image.Error)
                                    return ;

                                if (Qt.resolvedUrl(thumbnailImage.sourcePath) !== Qt.resolvedUrl(filePath))
                                    return ;

                                thumbnailImage.reload();
                            }

                            target: Wallpapers
                        }
                    }
                }

                // Folders and other non-image entries show a fixed size icon in
                // the middle of the picture area, like the icon view of a file
                // manager shows them, instead of an icon stretched over the
                // whole cell. The icon area itself is the themed background
                // of the cell.
                Loader {
                    id: folderIcon

                    active: !root.useThumbnail && root.width > 0 && root.height > 0
                    anchors.centerIn: parent
                    width: root.folderIconSize
                    height: root.folderIconSize

                    sourceComponent: DirectoryIcon {
                        width: root.folderIconSize
                        height: root.folderIconSize
                        // The icon is rendered at the size it is shown in, so
                        // it stays sharp instead of being scaled up.
                        sourceSize.width: root.folderIconSize
                        sourceSize.height: root.folderIconSize
                        fileModelData: root.fileModelData
                    }
                }

            }

            StyledText {
                id: wallpaperItemName

                visible: root.showLabel
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: (fileModelData && fileModelData.fileName) ? fileModelData.fileName : ""
                color: root.colText

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

            }

        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

    }

}
