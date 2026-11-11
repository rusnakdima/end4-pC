pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

/**
 * The single in-shell decode of the wallpaper video.
 *
 * The desktop keeps its own player (mpvpaper: external, hardware decoded,
 * driven by switchwall). Every surface INSIDE the shell renders the frames
 * of this one MediaPlayer through a shared VideoSink, so N visible previews
 * cost exactly one decode instead of N.
 *
 * Which file plays is decided by targetPath: a hovered picker cell
 * (overridePath) wins over a desktop preview (Wallpapers.previewPath),
 * which wins over the applied wallpaper. Surfaces only bind this sink when
 * their own path equals currentPath — everyone else keeps their still.
 */
Singleton {
    id: root

    property string overridePath: ""

    function requestOverride(path) {
        if (path && path.length > 0) root.overridePath = path;
    }

    function clearOverride(path) {
        if (path === undefined || root.overridePath === path) root.overridePath = "";
    }

    readonly property string targetPath: {
        if (root.overridePath.length > 0) return root.overridePath;
        return Wallpapers.previewPath || Config.options.background.wallpaperPath;
    }
    readonly property string currentPath: Images.isVideoPath(root.targetPath) ? root.targetPath : ""

    // One acquire per engaged surface: the decode exists only while somebody
    // is actually looking at it.
    property int consumers: 0
    function acquire() { root.consumers += 1 }
    function release() { root.consumers = Math.max(0, root.consumers - 1) }

    readonly property bool engaged: root.consumers > 0 && root.currentPath.length > 0
    // Paused in lockstep with the desktop player (sidebar toggle and the
    // battery policy both drive LiveWallpaper.paused).
    readonly property bool wantPlay: root.engaged && !LiveWallpaper.paused

    readonly property url mediaSource: {
        if (root.currentPath === "") return "";
        if (root.currentPath.startsWith("file://") || root.currentPath.startsWith("http"))
            return root.currentPath;
        return "file://" + root.currentPath;
    }

    // What the surfaces bind their VideoOutput to.
    readonly property var videoSink: sink

    VideoSink {
        id: sink
    }

    MediaPlayer {
        id: player
        source: root.engaged ? root.mediaSource : ""
        videoOutput: sink
        autoPlay: root.wantPlay
        loops: MediaPlayer.Infinite
        // Silent by construction: Qt 6 routes audio only through an
        // AudioOutput, and this player has none (MediaPlayer.muted no
        // longer exists in Qt 6.12).
    }

    // MediaPlayer is not an Item, so the playback control lives here as a
    // sibling instead of inside it.
    Connections {
        target: root
        function onWantPlayChanged() {
            if (root.wantPlay) player.play();
            else player.pause();
        }
    }

    // Diagnostics: qs -c end4-pC ipc call wallpaperstream status
    IpcHandler {
        target: "wallpaperstream"

        function status(): string {
            return JSON.stringify({
                consumers: root.consumers,
                engaged: root.engaged,
                overridePath: root.overridePath,
                currentPath: root.currentPath,
                wantPlay: root.wantPlay,
                playbackState: player.playbackState
            });
        }
    }
}
