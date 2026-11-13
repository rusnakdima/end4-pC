pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: panelRoot
        required property var modelData

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        // Same live-wallpaper handoff as the ii background: mpvpaper draws the
        // video below this layer, so the still has to step aside while it is
        // playing. Without this the waffle desktop pane covered the single
        // wallpaper player with a frozen frame.
        property string effectiveWallpaperPath:
            Wallpapers.previewPath || Wallpapers.confirmedPath
                || Config.options.background.wallpaperPath
        readonly property bool wallpaperIsVideo:
            Images.isVideoPath(effectiveWallpaperPath)
        readonly property bool previewingVideo:
            Wallpapers.previewPath.length > 0 && Images.isVideoPath(Wallpapers.previewPath)
        readonly property bool previewVideoWithoutPlayer:
            previewingVideo && !LiveWallpaper.previewPlayerActive
                && !LiveWallpaper.queryInFlight
        readonly property bool showLiveVideo:
            wallpaperIsVideo && !previewVideoWithoutPlayer
                && (previewingVideo || LiveWallpaper.available)

        StyledImage {
            anchors.fill: parent
            visible: !panelRoot.showLiveVideo
            // Drop the still entirely while the player is visible: keeping it
            // loaded would cost a second full-size wallpaper in memory for no
            // visible benefit.
            source: panelRoot.showLiveVideo
                ? ""
                : Wallpapers.displayPathFor(panelRoot.effectiveWallpaperPath)
            fillMode: Image.PreserveAspectCrop
        }
    }
}
