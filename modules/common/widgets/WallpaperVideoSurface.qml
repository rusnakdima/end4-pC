import QtQuick
import QtMultimedia
import qs
import qs.services
import qs.modules.common

/**
 * Renders the shared wallpaper decode (WallpaperStream) for exactly one file.
 *
 * Drop-in replacement for LiveWallpaperPreview: the caller's still Image
 * stays underneath and shows whenever this item is hidden — a different
 * file, an image wallpaper, or a moment the stream has no frames yet. No
 * instance ever decodes anything itself.
 *
 * Pass the RAW file path, never a thumbnail. Set retarget: true for
 * surfaces that show a file of their own choosing (picker cells): while
 * visible they ask the stream for their file, so hovering a cell plays it
 * through the shared decoder and releases it again on leave.
 */
VideoOutput {
    id: root

    property string path: ""
    property bool retarget: false

    readonly property bool isVideo: root.path !== "" && Images.isVideoPath(root.path)
    readonly property bool onScreen: root.Window.visibility !== Window.Hidden
    readonly property bool eligible: root.isVideo && root.onScreen
    // True once the stream is pointed at this surface's file.
    readonly property bool shared: root.eligible && root.path === WallpaperStream.currentPath
    readonly property bool engaged: root.shared

    visible: root.shared
    fillMode: VideoOutput.PreserveAspectCrop
    videoSink: root.shared ? WallpaperStream.videoSink : null

    function syncRequest() {
        if (!root.retarget) return;
        if (root.eligible) WallpaperStream.requestOverride(root.path);
        else if (WallpaperStream.overridePath === root.path) WallpaperStream.clearOverride(root.path);
    }

    Component.onCompleted: syncRequest()
    onEligibleChanged: syncRequest()
    onPathChanged: syncRequest()

    onEngagedChanged: {
        if (root.engaged) WallpaperStream.acquire();
        else WallpaperStream.release();
    }

    Component.onDestruction: {
        if (root.retarget && WallpaperStream.overridePath === root.path)
            WallpaperStream.clearOverride(root.path);
        if (root.engaged) WallpaperStream.release();
    }
}
