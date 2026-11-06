import QtQuick
import QtMultimedia
import qs
import qs.services
import qs.modules.common

/**
 * Plays a video wallpaper on top of whatever still a surface already shows.
 *
 * The desktop plays live wallpapers with an external mpvpaper process
 * (scripts/wallpapers/__video_wallpaper.sh); QML never decodes video, so
 * every settings and sidebar surface was frozen on a thumbnail by construction.
 * This adds the decode back, as an overlay: the still underneath stays visible
 * and keeps supplying the geometry, so a failed decode, a missing file or a
 * non-video path simply leaves the surface exactly as it was.
 *
 * Pass the RAW wallpaper path, never a thumbnail one -- the caller's own image
 * element is responsible for resolving thumbnails via Wallpapers.displayPathFor.
 */
Item {
    id: root

    property string path: ""

    readonly property bool isVideo: root.path !== "" && Images.isVideoPath(root.path)
    // Destroyed rather than paused when the window goes away: the surface no
    // longer exists, so there is nothing left to decode for.
    readonly property bool onScreen: root.Window.visibility !== Window.Hidden
    // Kept in sync with the desktop: the sidebar toggle and the battery policy
    // in services/LiveWallpaper.qml both drive this, so pausing the wallpaper
    // pauses these previews with it instead of leaving them fighting.
    readonly property bool shouldPlay: root.isVideo && !LiveWallpaper.paused

    readonly property url mediaSource: {
        if (root.path === "") return "";
        if (root.path.startsWith("file://") || root.path.startsWith("http"))
            return root.path;
        return "file://" + root.path;
    }

    Loader {
        anchors.fill: parent
        active: root.isVideo && root.onScreen

        // Qt 6.12's VideoOutput has no `source` property any more (only
        // fillMode/videoSink), so the MediaPlayer+VideoOutput pair does not
        // compile. Video is the type Qt ships for exactly this: it owns both
        // and aliases source, autoPlay, loops, fillMode and muted.
        sourceComponent: Video {
            id: video
            anchors.fill: parent
            source: root.mediaSource
            autoPlay: root.shouldPlay
            loops: MediaPlayer.Infinite
            fillMode: VideoOutput.PreserveAspectCrop
            // A wallpaper is silent everywhere else -- mpvpaper itself runs
            // with no-audio -- so a preview must never start talking.
            muted: true

            Connections {
                target: root
                function onShouldPlayChanged() {
                    if (root.shouldPlay) video.play();
                    else video.pause();
                }
            }
        }
    }
}
