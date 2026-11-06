import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/*
 * Pause and resume the live wallpaper. availability comes from the mpv IPC
 * socket, so on a still wallpaper the tile is shown disabled instead of
 * sitting there dead -- which is what the classic panel does by hiding it.
 */
QuickToggleModel {
    name: Translation.tr("Live wallpaper")
    available: LiveWallpaper.available
    toggled: LiveWallpaper.available && !LiveWallpaper.paused
    statusText: !LiveWallpaper.available
        ? Translation.tr("Not running")
        : (LiveWallpaper.paused ? Translation.tr("Paused") : Translation.tr("Playing"))
    icon: LiveWallpaper.paused ? "play_arrow" : "pause"
    mainAction: () => {
        LiveWallpaper.toggle()
    }
    tooltipText: Translation.tr("Live wallpaper")
}
