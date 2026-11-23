import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.ii.sidebarRight.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.classicStyle
import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks
import qs.modules.ii.sidebarRight.vpn
import qs.modules.ii.sidebarRight.hotspot
import qs.modules.ii.sidebarRight.iconPicker

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool showVpnDialog: false
    property bool showHotspotDialog: false
    property bool editMode: false
    property string editTab: Config.options.sidebar.quickToggles.style === "android" ? "toggles" : "layout"
    readonly property var editTabs: Config.options.sidebar.quickToggles.style === "android"
        ? [
            { id: "toggles", name: Translation.tr("Toggles"), icon: "toggle_on" },
            { id: "layout", name: Translation.tr("Layout"), icon: "dashboard_customize" }
        ]
        : [{ id: "layout", name: Translation.tr("Layout"), icon: "dashboard_customize" }]
    property bool showIconPickerDialog: false

    // editTab is writable (the toolbar sets it), so its initial binding is
    // gone after the user picks a tab. Switching the quick-toggle style in
    // Settings can then leave it on "toggles" while that tab no longer
    // exists; fall back to the first valid tab.
    Connections {
        target: Config.ready ? Config.options.sidebar.quickToggles : null
        function onStyleChanged() {
            if (!root.editTabs.some(tab => tab.id === root.editTab))
                root.editTab = root.editTabs.length > 0 ? root.editTabs[0].id : "layout";
        }
    }

    readonly property bool animatedEntrance: WM.compositor !== "hyprland"
    readonly property bool sidebarOpen: GlobalStates.sidebarRightOpen

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return filterDuplicatePlayers(realPlayers)
        const filtered = realPlayers.filter(p =>
            (p.identity ?? "").toLowerCase().includes(preferred) ||
            (p.desktopEntry ?? "").toLowerCase().includes(preferred)
        )
        if (filtered.length === 0) return filterDuplicatePlayers(realPlayers)
        return filterDuplicatePlayers(filtered)
    }

    function filterDuplicatePlayers(players) {
        if (!players) return [];
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];

            // Find duplicates by trackTitle prefix
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                if (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (Math.abs(p1.position - p2.position) <= 2 && Math.abs(p1.length - p2.length) <= 2)) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx]?.trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    Connections {
        target: Vpn
        function onDialogRequested() { root.showVpnDialog = true; }
    }

    Connections {
        target: GlobalStates
        function onRequestBluetoothDialog() {
            if (!BluetoothStatus.available) return;
            root.showBluetoothDialog = true;
            GlobalStates.sidebarRightOpen = true;
        }

        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.editMode = false;
                root.showWifiDialog = false;
                root.showVpnDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
            }
        }
    }

    Process {
        id: fileChooser
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") + "/Pictures", "image/png image/jpg image/jpeg image/webp"]
        
        stdout: StdioCollector {
            id: fileChooserOutput
        }
        
        onExited: (code) => {
            if (code === 0) {
                const path = fileChooserOutput.text.trim()
                if (path !== "") {
                    Config.options.sidebar.bannerImage = path
                }
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground
        WindowGlass {
            anchors.fill: parent
            glassEnabled: (parent?.color.a ?? 0) > 0
            cardRadius: parent?.radius ?? 0
            tint: parent?.color ?? 'transparent'
        }

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colUiBackground
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.8) 
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 5

        // The sections keep their own heights (the notification card has a
        // fixed one), so on a short screen the column can be taller than the
        // panel. A Flickable gives it a scroll of its own instead of letting
        // the last cards spill past the rounded background; the touchpad
        // handler and a thin scrollbar come with StyledFlickable.
        StyledFlickable {
            id: sectionScroll
            anchors.fill: parent
            anchors.margins: sidebarPadding
            contentWidth: width
            contentHeight: sectionColumn.implicitHeight
            clip: true

            ReorderableColumn {
                id: sectionColumn
                // At least the viewport, so a column shorter than the panel
                // still starts at the top and any fill slot keeps working.
                width: sectionScroll.width
                height: Math.max(sectionScroll.height, sectionColumn.implicitHeight)
                itemSpacing: sidebarPadding
                order: root.sectionOrder
                editMode: root.editMode && root.editTab === "layout"
                onReordered: newOrder => Config.options.sidebar.sectionOrder = newOrder
                componentForKey: key => root.sectionComponents[key] ?? null
                isKeyActive: key => root.sectionActive(key)
            }
        }
    }

    readonly property var sectionComponents: ({
        "banner": bannerSection,
        "quickToggles": quickTogglesSection,
        "sliders": slidersSection,
        "media": mediaSection,
        "notifications": notificationsSection,
        "bottom": bottomSection
    })

    function sectionActive(key) {
        const sidebar = Config.options.sidebar
        switch (key) {
        case "sliders":
            return sidebar.quickSliders.enable && (sidebar.quickSliders.showMic || sidebar.quickSliders.showVolume || sidebar.quickSliders.showBrightness || sidebar.quickSliders.showKeyboardBrightness)
        case "media":
            return root.activePlayer !== null && sidebar.mediaPlayer
        case "bottom":
            return sidebar.bottomGroup
        default:
            return true
        }
    }

    readonly property var defaultSectionOrder: ["banner", "quickToggles", "sliders", "media", "notifications", "bottom"]
    readonly property var sectionOrder: {
        const saved = Array.from(Config.options.sidebar.sectionOrder).filter(key => defaultSectionOrder.includes(key))
        const unique = saved.filter((key, i) => saved.indexOf(key) === i)
        return unique.concat(defaultSectionOrder.filter(key => !unique.includes(key)))
    }

    Component {
        id: bannerSection
        Loader {
            sourceComponent: Config.options.sidebar.banner ? bannerComponent : normalComponent
        }
    }

        Component {
            id: bannerComponent
            Item {
                // The banner keeps the source aspect ratio: the height is
                // derived from the panel width instead of cropping the picture
                // into a fixed 120px strip. A 16:9 wallpaper therefore gets a
                // 16:9 banner, and a 4:3 one gets a 4:3 banner.
                implicitHeight: wallpaperRect.height + 2 * sysRect.inset
                implicitWidth: parent?.width ?? 0

                Rectangle {
                    id: sysRect
                    WindowGlass {
                        anchors.fill: parent
                        glassEnabled: (parent?.color.a ?? 0) > 0
                        cardRadius: parent?.radius ?? 0
                        tint: parent?.color ?? 'transparent'
                    }
                    readonly property real inset: 5
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    Rectangle {
                        id: wallpaperRect
                        readonly property real aspect: bannerMedia.imageAspectRatio > 0
                            ? bannerMedia.imageAspectRatio
                            : (bannerMedia.isVideo ? 16 / 9 : 16 / 9)

                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            topMargin: sysRect.inset
                            leftMargin: sysRect.inset
                            rightMargin: sysRect.inset
                        }
                        // Full source height, no vertical crop.
                        height: width / aspect
                        radius: Math.max(0, sysRect.radius - sysRect.inset)
                        color: "transparent"

                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: wallpaperRect.width
                                    height: wallpaperRect.height
                                    radius: wallpaperRect.radius
                                }
                            }

                            WallpaperMedia {
                                id: bannerMedia
                                anchors.fill: parent
                                // The container already has the source's aspect
                                // ratio, so Fit is exact; nothing is cropped.
                                fillMode: Image.PreserveAspectFit
                                // Raw path: an image is shown directly, a clip plays.
                                source: Config.options.sidebar.bannerImage !== ""
                                    ? Config.options.sidebar.bannerImage
                                    : Config.options.background.wallpaperPath
                                // Follow the desktop's playback clock: the
                                // banner shows the same part of the clip as the
                                // desktop and the settings preview.
                                syncGroup: Config.options.background.inShellVideo
                                    && Config.options.sidebar.bannerImage === ""
                                    && WallpaperVideo.desktopRawSource === Config.options.background.wallpaperPath
                                    ? "desktop"
                                    : ""
                                playing: !LiveWallpaper.paused
                                // Reuse the generated still: a banner decoder
                                // would decode the desktop clip a second time
                                // and stutter the panel every time it opens.
                                allowLive: false
                                stillSourceSize: Qt.size(wallpaperRect.width * 2, wallpaperRect.height * 2)
                                cacheStill: true
                                antialiasing: true
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (event) => {
                                if (event.button === Qt.LeftButton) {
                                    fileChooser.running = true
                                    GlobalStates.sidebarRightOpen = false
                                } else if (event.button === Qt.RightButton) {
                                    Config.options.sidebar.bannerImage = ""
                                    Config.options.sidebar.bannerFocusX = 0.5
                                    Config.options.sidebar.bannerFocusY = 0.5
                                }
                            }
                        }
                    }

                    Item {
                        // The profile and the quick actions sit on top of the
                        // picture now, so they get a glass strip that samples
                        // the poster/video underneath instead of a flat colour.
                        id: bannerFooter
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 88

                        FrostedGlass {
                            anchors.fill: parent
                            blurSource: bannerMedia
                            topLeftRadius: 0
                            topRightRadius: 0
                            bottomLeftRadius: sysRect.radius
                            bottomRightRadius: sysRect.radius
                            tint: Appearance.colors.colLayer1
                            tintOpacity: 0.42
                        }
                    }

                    Column {
                        anchors {
                            left: bannerFooter.left
                            bottom: bannerFooter.bottom
                            leftMargin: sysRect.inset + 8
                            bottomMargin: 6
                        }
                        spacing: 1

                        UserAvatar {
                            width: 48
                            height: 48
                        }

                        StyledText {
                            text: (Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName) + "@" + SystemInfo.hostname
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: Translation.tr("Up • %1").arg(DateTime.uptime)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.6
                        }
                    }

                    ButtonGroup {
                        anchors {
                            right: bannerFooter.right
                            verticalCenter: bannerFooter.verticalCenter
                            margins: 8
                        }
                        color: "transparent"
                        padding: 4

                        QuickToggleButton {
                            toggled: root.editMode
                                        buttonIcon: "edit"
                            onClicked: root.editMode = !root.editMode
                            StyledToolTip {
                                text: Translation.tr("Edit sidebar")
                            }
                        }
                        QuickToggleButton {
                            toggled: false
                            buttonIcon: "restart_alt"
                            onClicked: {
                                Quickshell.execDetached(["hyprctl", "reload"])
                                GlobalStates.requestShellReload();
                            }
                            StyledToolTip {
                                text: Translation.tr("Reload Hyprland & Quickshell")
                            }
                        }
                        QuickToggleButton {
                            toggled: GlobalStates.settingsOpen
                            buttonIcon: "settings"
                            onClicked: {
                                GlobalStates.sidebarRightOpen = false;
                                GlobalStates.settingsOpen = !GlobalStates.settingsOpen
                            }
                            StyledToolTip {
                                text: Translation.tr("Settings")
                            }
                        }
                        QuickToggleButton {
                            toggled: false
                            buttonIcon: "mode_off_on"
                            onClicked: GlobalStates.sessionOpen = true
                            StyledToolTip {
                                text: Translation.tr("Session")
                            }
                        }
                    }
                }
            }
        }

    Component {
        id: normalComponent
        SystemButtonRow {}
    }

    Component {
        id: quickTogglesSection
        Item {
            id: togglesSection

            // Spoiler for the toggle grid, same idea as the two cards. This
            // section is never a fill slot: its own implicitHeight carries
            // the header in both states and takes a step when it collapses;
            // the slot Behavior in ReorderableColumn smooths that step and
            // slides the sections below it.
            readonly property bool collapsed: Persistent.states.sidebar.quickToggles.collapsed
            // 4 px above the header + the header + 4 px below it: a collapsed
            // row measures 48 px, the same as a collapsed sliders card.
            // Expanding adds the gap the panel needs under the header and the
            // panel's own height.
            implicitHeight: 8 + header.implicitHeight
                + (togglesSection.collapsed ? 0
                    : 4 + (classicLoader.item?.implicitHeight ?? 0)
                        + (androidLoader.item?.implicitHeight ?? 0))

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.normal
                // Painted unconditionally, exactly like the sliders and
                // notification cards. It used to be conditional on the glass
                // setting, which with glass off left this spoiler header
                // floating on the bare sidebar while the panel below drew its
                // own card - the one row that did not match the other two.
                // The panels now stay transparent so there is still only one
                // card (they used to be the card).
                color: Appearance.colors.colLayer1
                // The collapsible cards all wear the same hairline.
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.55)

                WindowGlass {
                    anchors.fill: parent
                    glassEnabled: parent.color.a > 0
                    cardRadius: parent.radius
                    tint: parent.color
                }
            }

            CollapsibleSectionHeader {
                id: header
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 4
                    // Same 12 px inset as the sliders card, so the icon and
                    // label line up with that header.
                    leftMargin: 12
                    rightMargin: 12
                }
                headerIcon: "toggle_on"
                title: Translation.tr("Quick toggles")
                collapsed: togglesSection.collapsed
                // The header reports the tap; the state is written here so
                // the Persistent binding is never broken by the child.
                onCollapseToggled: Persistent.states.sidebar.quickToggles.collapsed = !Persistent.states.sidebar.quickToggles.collapsed
            }

            Loader {
                id: classicLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    top: header.bottom
                    topMargin: 4
                }
                visible: !togglesSection.collapsed
                active: Config.options.sidebar.quickToggles.style === "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            Loader {
                id: androidLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    top: header.bottom
                    topMargin: 4
                }
                visible: !togglesSection.collapsed
                active: Config.options.sidebar.quickToggles.style === "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode && root.editTab === "toggles"
                }
            }

            Connections {
                target: classicLoader.item
                function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true; }
                function onOpenAudioInputDialog() { root.showAudioInputDialog = true; }
                function onOpenBluetoothDialog() { root.showBluetoothDialog = true; }
                function onOpenNightLightDialog() { root.showNightLightDialog = true; }
                function onOpenWifiDialog() { root.showWifiDialog = true; }
                function onOpenVpnDialog() { root.showVpnDialog = true; }
                function onOpenHotspotDialog() { root.showHotspotDialog = true; }
            }

            Connections {
                target: androidLoader.item
                function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true; }
                function onOpenAudioInputDialog() { root.showAudioInputDialog = true; }
                function onOpenBluetoothDialog() { root.showBluetoothDialog = true; }
                function onOpenNightLightDialog() { root.showNightLightDialog = true; }
                function onOpenWifiDialog() { root.showWifiDialog = true; }
                function onOpenVpnDialog() { root.showVpnDialog = true; }
                function onOpenHotspotDialog() { root.showHotspotDialog = true; }
            }
        }
    }

    Component {
        id: slidersSection
        Loader {
            active: root.sectionActive("sliders")
            sourceComponent: QuickSliders {}
        }
    }

    Component {
        id: mediaSection
        Loader {
            active: root.sectionActive("media") && GlobalStates.sidebarRightOpen
            sourceComponent: Item {
                implicitHeight: 160 - Appearance.sizes.elevationMargin * 2

                Player {
                    anchors.fill: parent
                    anchors.margins: -Appearance.sizes.elevationMargin
                    player: root.activePlayer
                    visualizerPoints: GlobalStates.visualizerPoints
                    radius: Appearance.rounding.normal
                }
            }
        }
    }

    Component {
        id: notificationsSection
        CenterWidgetGroup {}
    }

    Component {
        id: bottomSection
        Loader {
            active: root.sectionActive("bottom")
            sourceComponent: BottomWidgetGroup {}
        }
    }

    Toolbar {
        id: editToolbar
        glass: true
        z: 60
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.editMode ? 22 : -height - 30
        opacity: root.editMode ? 1 : 0

        Behavior on anchors.bottomMargin {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        ToolbarTabBar {
            id: editTabBar
            tabButtonList: root.editTabs
            currentIndex: Math.max(0, root.editTabs.findIndex(tab => tab.id === root.editTab))
            onCurrentIndexChanged: root.editTab = root.editTabs[Math.max(0, currentIndex)]?.id ?? "layout"
        }

        IconToolbarButton {
            text: "check"
            onClicked: root.editMode = false
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                BluetoothStatus.stopDiscovery();
            } else {
                BluetoothStatus.setPowerAndDiscover(true);
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showVpnDialog"
        dialog: VpnDialog {}
        onShownChanged: if (shown) Vpn.refresh()
    }

    ToggleDialog {
        shownPropertyString: "showHotspotDialog"
        dialog: HotspotDialog {}
        onShownChanged: if (shown) Hotspot.refresh()
    }

    ToggleDialog {
        shownPropertyString: "showIconPickerDialog"
        dialog: IconPickerDialog {}
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (toggleDialogLoader.item && !toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString])
                    toggleDialogLoader.active = false;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            implicitWidth: uptimeRow.implicitWidth + 24
            implicitHeight: uptimeRow.implicitHeight + 8

            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: 8
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25

                    CustomIcon {
                        id: distroIcon
                        anchors.fill: parent
                        source: Config.options.custom.distroIcon || SystemInfo.distroIcon
                        customFolder: Config.options.custom.iconsPath
                        colorize: Config.options.custom.colorizeIcon
                        color: Appearance.colors.colOnLayer0
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showIconPickerDialog = true
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("Up • %1").arg(DateTime.uptime)
                    textFormat: Text.MarkdownText
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: 4

            QuickToggleButton {
                toggled: root.editMode
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit sidebar")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    if (WM.compositor === "niri") {
                        Quickshell.execDetached(["niri", "msg", "action", "reload-config"]);
                    } else {
                        Quickshell.execDetached(["hyprctl", "reload"]);
                    }
                    GlobalStates.requestShellReload();
                }
                StyledToolTip {
                    text: WM.compositor === "niri"
                        ? Translation.tr("Reload Niri & Quickshell")
                        : Translation.tr("Reload Hyprland & Quickshell")
                }
            }
            QuickToggleButton {
                toggled: GlobalStates.settingsOpen
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    GlobalStates.settingsOpen = !GlobalStates.settingsOpen
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "mode_off_on"
                onClicked: GlobalStates.sessionOpen = true
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
