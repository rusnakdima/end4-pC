pragma ComponentBehavior: Bound

import QtMultimedia
import QtQuick
import QtQuick.Window
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * One wallpaper preview surface: the still of `source`, or the clip itself.
 *
 * `source` is always the RAW wallpaper path, never a thumbnail. An image is
 * shown with a plain Image under a sourceSize cap; a video gets the same still
 * underneath (so the surface is never blank while the decoder starts) and a
 * muted looping Video on top. The still remains the fallback when the clip
 * cannot be opened, so a broken file degrades to the poster instead of to a
 * black rectangle.
 *
 * Every surface that needs this uses ONE instance of this component with its
 * own `source`, instead of keeping a still Image and a separate player in
 * sync. This also replaces the frame_stream.py pipeline the picker used to
 * run (ffmpeg -> base64 -> one Image reload per frame), which capped the
 * hovered cell at a few frames per second; QtMultimedia decodes the clip
 * directly.
 */
Item {
    id: media

    // Raw path of the wallpaper. Images and videos are both accepted.
    property string source: ""
    // "desktop" or "lock" follows the shared playback clock, so previews
    // opened later join the clip at the position that is already on screen.
    // Empty means a transient preview (the picker) that may start at zero.
    property string syncGroup: ""
    // Videos are played through the scaled proxy. The picker sets this false
    // so a hovered clip starts immediately instead of waiting for an encode.
    property bool useProxy: true
    property string playbackPath: ""
    // Pause keeps the still on screen and stops the decoder.
    property bool playing: true
    // Set false where the caller already paints the still (picker cells).
    property bool showStill: true
    // Image.PreserveAspectCrop / PreserveAspectFit / Stretch. The values are
    // the same as VideoOutput's fill modes.
    property int fillMode: Image.PreserveAspectCrop
    // Cap for the still decode, so a 4K poster is not decoded at full size.
    property size stillSourceSize: Qt.size(0, 0)
    property bool cacheStill: true

    readonly property bool isVideo: media.source.length > 0 && Images.isVideoPath(media.source)
    readonly property bool videoReady: media.isVideo && video.hasVideo
        && video.error === MediaPlayer.NoError
    // Exposed so a caller can tell whether the clip is actually moving, and
    // so the tests do not have to reach into the private Video.
    readonly property int playbackState: video.playbackState
    readonly property int position: video.position
    // True once the clip is actually running, not merely loaded. Callers use
    // this to keep a still up until there is something to show.
    readonly property bool playingNow: media.active
        && video.playbackState === MediaPlayer.PlayingState
    readonly property url mediaUrl: {
        if (!media.isVideo) return "";
        const resolved = media.useProxy ? media.playbackPath : media.source;
        if (resolved.length === 0) return "";
        const path = String(resolved);
        if (path.startsWith("file://") || path.startsWith("http://") || path.startsWith("https://"))
            return path;
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }
    // The group's elapsed time, and the position this clip should be at.
    // `syncTarget` is -1 until the duration is known; joining a clip late
    // seeks to it instead of starting from zero.
    readonly property real syncElapsed: media.syncGroup === "desktop"
        ? WallpaperVideo.desktopElapsed
        : (media.syncGroup === "lock" ? WallpaperVideo.lockElapsed : 0)
    readonly property real syncTarget: {
        if (media.syncGroup === "" || !media.videoReady || video.duration <= 0) return -1;
        return media.syncElapsed % video.duration;
    }

    onSyncTargetChanged: {
        if (media.syncTarget < 0 || !video.seekable) return;
        const drift = Math.abs(video.position - media.syncTarget);
        // A position near the loop seam looks like a huge drift; the loop
        // will wrap it naturally.
        if (drift > 50 && drift < video.duration - 50)
            video.position = media.syncTarget;
    }
    onVideoReadyChanged: {
        if (!media.videoReady) return;
        if (media.syncTarget >= 0 && video.seekable)
            video.position = media.syncTarget;
    }

    Process {
        id: proxyProc
        // A reply for a source that another change replaced must not become
        // this surface's playback file.
        property string sourcePath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (proxyProc.sourcePath !== media.source) return;
                media.playbackPath = text.trim();
            }
        }
    }

    onSourceChanged: {
        proxyProc.running = false;
        media.playbackPath = "";
        if (!media.isVideo || !media.useProxy || media.source.length === 0) return;
        proxyProc.sourcePath = media.source;
        proxyProc.command = ["bash", Directories.videoWallpaperScriptPath, "--prefetch", media.source];
        proxyProc.running = true;
    }
    onUseProxyChanged: {
        proxyProc.running = false;
        media.playbackPath = "";
        if (!media.isVideo || !media.useProxy || media.source.length === 0) return;
        proxyProc.sourcePath = media.source;
        proxyProc.command = ["bash", Directories.videoWallpaperScriptPath, "--prefetch", media.source];
        proxyProc.running = true;
    }
    Component.onCompleted: {
        if (!media.isVideo || !media.useProxy || media.source.length === 0) return;
        proxyProc.sourcePath = media.source;
        proxyProc.command = ["bash", Directories.videoWallpaperScriptPath, "--prefetch", media.source];
        proxyProc.running = true;
    }
    // The still for an image is the image itself. For a clip it is the poster
    // the wallpaper pipeline already generated for the current wallpaper; any
    // other clip falls back to the freedesktop thumbnail, rendered on demand
    // by ThumbnailImage below.
    readonly property string stillSource: {
        if (media.source.length === 0) return "";
        if (!media.isVideo) return media.source;
        return Wallpapers.videoStillFor(media.source);
    }
    // A closed sidebar or settings window keeps the item's own `visible`
    // property true, so the window has to be checked as well; otherwise the
    // banner would keep decoding a clip behind a hidden window.
    readonly property bool active: media.playing && media.visible
        && (Window.window === null || Window.window.visible)
    // A clip without the generated still of the current wallpaper still needs
    // a picture: ThumbnailImage below renders one and caches it. It stays for
    // as long as the still is missing, including while the clip plays, so the
    // settings glass can always sample a picture and the card never flashes
    // the empty background.
    readonly property bool posterNeeded: media.isVideo && media.stillSource === ""
        && media.showStill && media.source.length > 0

    // Exposed for surfaces that need the still itself, e.g. the glass blur in
    // the settings hero card, which must sample a still and not every frame.
    readonly property Item stillItem: (media.isVideo && media.stillSource === "")
        ? posterLoader
        : still
    readonly property int imageStatus: {
        const item = media.isVideo && media.stillSource === ""
            ? posterLoader.item
            : still;
        return item ? item.status : Image.Null;
    }
    readonly property real imageAspectRatio: {
        const item = media.isVideo && media.stillSource === ""
            ? posterLoader.item
            : still;
        if (!item || item.implicitHeight <= 0) return 0;
        return item.implicitWidth / item.implicitHeight;
    }

    Image {
        id: still

        anchors.fill: parent
        visible: media.showStill && media.source.length > 0 && media.stillSource !== ""
        source: media.showStill && media.stillSource !== "" ? media.stillSource : ""
        fillMode: media.fillMode
        asynchronous: true
        retainWhileLoading: true
        cache: media.cacheStill
        smooth: true
        mipmap: false
        antialiasing: media.antialiasing
        sourceSize.width: media.stillSourceSize.width
        sourceSize.height: media.stillSourceSize.height
        opacity: status === Image.Ready ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // A video that has no poster yet: ThumbnailImage generates a freedesktop
    // thumbnail (ffmpeg frame) once and caches it, so a card that is not
    // focused still shows what the clip looks like.
    Loader {
        id: posterLoader

        anchors.fill: parent
        active: media.posterNeeded
        visible: media.showStill

        sourceComponent: ThumbnailImage {
            anchors.fill: parent
            sourcePath: media.source
            fillMode: media.fillMode
            sourceSize.width: media.stillSourceSize.width
            sourceSize.height: media.stillSourceSize.height
        }
    }

    Video {
        id: video

        anchors.fill: parent
        // hasVideo is false until the clip has been opened, so the still (or
        // the caller's own thumbnail) stays visible instead of a black frame.
        visible: media.isVideo && media.active && media.videoReady
        source: media.isVideo ? media.mediaUrl : ""
        autoPlay: media.active
        loops: MediaPlayer.Infinite
        muted: true
        fillMode: media.fillMode

        onVisibleChanged: {
            if (media.active) video.play();
            else video.pause();
        }
    }

    onActiveChanged: {
        if (media.active) {
            if (media.syncTarget >= 0 && video.seekable)
                video.position = media.syncTarget;
            if (video.playbackState !== MediaPlayer.PlayingState) video.play();
        } else {
            video.pause();
        }
    }
}
