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

        sourceComponent: Item {
            anchors.fill: parent

            MediaPlayer {
                id: player
                source: root.mediaSource
                loops: MediaPlayer.Infinite
                autoPlay: root.shouldPlay
            }

            Connections {
                target: root
                function onShouldPlayChanged() {
                    if (root.shouldPlay) player.play();
                    else player.pause();
                }
            }

            VideoOutput {
                anchors.fill: parent
                source: player
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }
}
