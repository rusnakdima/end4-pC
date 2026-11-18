pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Shared playback clock for the in-shell wallpaper videos.
 *
 * Qt's VideoOutput does not let QML elements share a VideoSink, so every
 * surface decodes the same proxy itself. They all follow the elapsed time of
 * this singleton instead of starting from zero when they are created, which
 * is what keeps the desktop, the right-panel banner and the settings cards on
 * the same part of the clip. WallpaperMedia seeks its own player to the group
 * position when it joins and corrects larger drift while it runs.
 *
 * `desktop` is the wallpaper currently on the desktop (a picker preview wins
 * over the applied one). `lock` is the lock wallpaper. When both modes use the
 * same file, the lock surfaces use the desktop clock so the two cannot drift
 * apart either.
 */
Singleton {
    id: root

    readonly property string desktopRawSource: {
        if (Wallpapers.previewPath.length > 0 && Images.isVideoPath(Wallpapers.previewPath))
            return Wallpapers.previewPath;
        return Config.options.background.wallpaperPath;
    }
    readonly property string lockRawSource: Config.options.background.lockWall !== ""
        ? Config.options.background.lockWall
        : Config.options.background.wallpaperPath
    readonly property bool lockSharesDesktop: root.lockRawSource === root.desktopRawSource
    readonly property bool inShell: Config.options.background.inShellVideo

    // One epoch per independent clip. Elapsed is read by the players; the
    // wall clock is the master, so a player that buffers does not drag the
    // other surfaces with it.
    property double desktopEpoch: Date.now()
    property double lockEpoch: Date.now()
    property double desktopElapsed: 0
    property double lockElapsed: 0
    property double pausedAt: 0
    readonly property bool paused: LiveWallpaper.paused

    onDesktopRawSourceChanged: {
        root.desktopEpoch = Date.now();
        root.desktopElapsed = 0;
    }
    onLockRawSourceChanged: {
        root.lockEpoch = Date.now();
        root.lockElapsed = 0;
    }
    onPausedChanged: {
        const now = Date.now();
        if (root.paused) {
            root.pausedAt = now;
        } else if (root.pausedAt > 0) {
            // Continue where the pause started instead of jumping ahead.
            const delta = now - root.pausedAt;
            root.desktopEpoch += delta;
            root.lockEpoch += delta;
            root.pausedAt = 0;
        }
    }

    // Called when the theme/shell comes back (startup, reload, re-applied
    // wallpaper). Every surface joins the clip at the start again instead of
    // guessing an epoch from a stale process.
    function restart(): void {
        const now = Date.now();
        root.desktopEpoch = now;
        root.lockEpoch = now;
        root.desktopElapsed = 0;
        root.lockElapsed = 0;
        root.pausedAt = 0;
    }

    IpcHandler {
        target: "wallpaperVideo"
        function restart(): void { root.restart() }
        function status(): string {
            return JSON.stringify({
                desktopSource: root.desktopRawSource,
                lockSource: root.lockRawSource,
                desktopElapsed: root.desktopElapsed,
                lockElapsed: root.lockElapsed,
                paused: root.paused
            });
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (root.paused) return;
            const now = Date.now();
            root.desktopElapsed = now - root.desktopEpoch;
            root.lockElapsed = now - root.lockEpoch;
        }
    }
}
