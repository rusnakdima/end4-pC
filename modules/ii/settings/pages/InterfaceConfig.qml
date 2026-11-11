import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "settings"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Settings Panel")
            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: Config.options.settings.style
                    onSelected: newValue => { Config.options.settings.style = newValue }
                    options: [
                        { displayName: Translation.tr("Default"), icon: "settings_panorama", value: "default" },
                        { displayName: Translation.tr("Minimal"), icon: "settings_heart", value: "minimal" },
                        { displayName: Translation.tr("Dashboard"), icon: "dashboard", value: "dashboard" }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Sidebar")
                    icon: "left_panel_open"
                    currentValue: Config.options.settings.sidebarDensity
                    onSelected: newValue => { Config.options.settings.sidebarDensity = newValue }
                    options: [
                        { displayName: Translation.tr("Default"), icon: "unfold_more", value: "default" },
                        { displayName: Translation.tr("Compact"), icon: "density_small", value: "compact" }
                    ]
                }
                ConfigSelectionArray {
                    enabled: Config.options.settings.style === "dashboard"
                    text: Translation.tr("Dashboard animation speed")
                    icon: "speed"
                    currentValue: Config.options.settings.animationSpeed
                    onSelected: newValue => { Config.options.settings.animationSpeed = newValue }
                    options: [
                        { displayName: "1x", icon: "slow_motion_video", value: 1 },
                        { displayName: "1.5x", icon: "play_arrow", value: 1.5 },
                        { displayName: "2x", icon: "fast_forward", value: 2 },
                        { displayName: "3x", icon: "bolt", value: 3 }
                    ]
                }
                ConfigSpinBox {
                    icon: "border_style"
                    text: Translation.tr("Border width")
                    value: Config.options.settings.borderSize
                    from: 0
                    to: 10
                    stepSize: 1
                    onValueChanged: { Config.options.settings.borderSize = value }
                }
                ColorSelectionArray {
                    icon: "format_paint"
                    text: Translation.tr("Border Color")
                    options: ["primary", "secondary", "tertiary", "primaryContainer", "secondaryContainer", "tertiaryContainer", "layer0Border"]
                    currentValue: Config.options.settings.borderColor 
                    onSelected: newValue => {
                        Config.options.settings.borderColor = newValue
                    }
                }
            } 
        }

        ContentSection {
            icon: "splitscreen_left"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Left Sidebar")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: mediaCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: "transparent"

                    ColumnLayout {
                        id: mediaCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        MaterialSymbol {
                            text: "music_note_2"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Media Player")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                        Item { Layout.fillHeight: true }
                        GroupedList {
                            Layout.fillWidth: true
                            bgcolor: Appearance.colors.colLayer2
                            ConfigSwitch {
                                buttonIcon: "check"
                                text: Translation.tr("Enable")
                                checked: Config.options.sidebar.media.enable
                                onCheckedChanged: { Config.options.sidebar.media.enable = checked }
                            }
                            ConfigSwitch {
                                buttonIcon: "radio_button_partial"
                                text: Translation.tr("Follow Album Colors")
                                checked: Config.options.sidebar.media.artColors
                                onCheckedChanged: { Config.options.sidebar.media.artColors = checked }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: aiCol.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: "transparent"

                        ColumnLayout {
                            id: aiCol
                            anchors { fill: parent; margins: 12 }
                            spacing: 8

                            MaterialSymbol {
                                text: "smart_toy"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("AI")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                currentValue: Config.options.policies.ai
                                onSelected: newValue => { Config.options.policies.ai = newValue }
                                options: [
                                    { displayName: Translation.tr("No"), icon: "close", value: 0 },
                                    { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                                    { displayName: Translation.tr("Local"), icon: "sync_saved_locally", value: 2 }
                                ]
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: weebCol.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: "transparent"

                        ColumnLayout {
                            id: weebCol
                            anchors { fill: parent; margins: 12 }
                            spacing: 8

                            MaterialSymbol {
                                text: "playing_cards"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("Weeb")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                currentValue: Config.options.policies.weeb
                                onSelected: newValue => { Config.options.policies.weeb = newValue }
                                options: [
                                    { displayName: Translation.tr("No"), icon: "close", value: 0 },
                                    { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                                    { displayName: Translation.tr("Closet"), icon: "ev_shadow", value: 2 }
                                ]
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: translatorCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: "transparent"

                ColumnLayout {
                    id: translatorCol
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        ConfigSwitch {
                            buttonIcon: "translate"
                            text: Translation.tr("Enable Translator")
                            checked: Config.options.sidebar.translator.enable
                            onCheckedChanged: { Config.options.sidebar.translator.enable = checked }
                        }
                        ConfigSwitch {
                            buttonIcon: "sports_soccer"
                            text: Translation.tr("Football")
                            checked: Config.options.sidebar.football.enable
                            onCheckedChanged: { Config.options.sidebar.football.enable = checked }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "splitscreen_right"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Right Sidebar")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "planner_banner_ad_pt"
                    text: Translation.tr('Banner')
                    checked: Config.options.sidebar.banner
                    onCheckedChanged: {
                        Config.options.sidebar.banner = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "bottom_navigation"
                    text: Translation.tr('Bottom Group')
                    checked: Config.options.sidebar.bottomGroup
                    onCheckedChanged: {
                        Config.options.sidebar.bottomGroup = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr('Media Player')
                    checked: Config.options.sidebar.mediaPlayer
                    onCheckedChanged: {
                        Config.options.sidebar.mediaPlayer = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr('Keep right sidebar loaded')
                    checked: Config.options.sidebar.keepRightSidebarLoaded
                    onCheckedChanged: {
                        Config.options.sidebar.keepRightSidebarLoaded = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Quick toggles")
                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Style")
                        icon: "toggle_on"
                        Layout.fillWidth: false
                        currentValue: Config.options.sidebar.quickToggles.style
                        onSelected: newValue => {
                            Config.options.sidebar.quickToggles.style = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Classic"),
                                icon: "password_2",
                                value: "classic"
                            },
                            {
                                displayName: Translation.tr("Android"),
                                icon: "action_key",
                                value: "android"
                            }
                        ]
                    }
                    ConfigSpinBox {
                        enabled: Config.options.sidebar.quickToggles.style === "android"
                        icon: "add_column_left"
                        text: Translation.tr("Columns")
                        value: Config.options.sidebar.quickToggles.android.columns
                        from: 1
                        to: 8
                        stepSize: 1
                        onValueChanged: {
                            Config.options.sidebar.quickToggles.android.columns = value;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Sliders")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.quickSliders.enable
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.enable = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "brightness_6"
                        text: Translation.tr("Brightness")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showBrightness
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showBrightness = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "volume_up"
                        text: Translation.tr("Volume")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showVolume
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showVolume = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "mic"
                        text: Translation.tr("Microphone")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showMic
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showMic = checked;
                        }
                    }

                    // Label and control key have to match exactly:
                    // SettingsQuickControls.find() resolves a search hit as
                    // `pageId:section/subsection/label`.
                    ConfigSwitch {
                        buttonIcon: "keyboard"
                        text: Translation.tr("Keyboard Brightness")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showKeyboardBrightness
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showKeyboardBrightness = checked;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "screenshot_frame_2"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Hot Corners")

            ContentSubsection {
                title: Translation.tr("Top")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.cornerOpen.enable
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.enable = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "highlight_mouse_cursor"
                        text: Translation.tr("Hover to trigger")
                        checked: Config.options.sidebar.cornerOpen.clickless
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.clickless = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "vertical_align_bottom"
                        text: Translation.tr("Place at bottom")
                        checked: Config.options.sidebar.cornerOpen.bottom
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.bottom = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "unfold_more_double"
                        text: Translation.tr("Value scroll")
                        checked: Config.options.sidebar.cornerOpen.valueScroll
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.valueScroll = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "visibility"
                        text: Translation.tr("Visualize region")
                        checked: Config.options.sidebar.cornerOpen.visualize
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.visualize = checked }
                    }
                    ConfigSwitch {
                        enabled: Config.options.sidebar.cornerOpen.clickless
                        buttonIcon: "ads_click"
                        text: Translation.tr("Force hover at absolute corner")
                        checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked }
                    }
                    ConfigSpinBox {
                        enabled: Config.options.sidebar.cornerOpen.clickless
                        icon: "arrow_cool_down"
                        text: Translation.tr("Vertical offset")
                        value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                        from: 0; to: 20; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value }
                    }
                    ConfigSpinBox {
                        icon: "arrow_range"
                        text: Translation.tr("Region width")
                        value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                        from: 1; to: 300; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.cornerRegionWidth = value }
                    }
                    ConfigSpinBox {
                        icon: "height"
                        text: Translation.tr("Region height")
                        value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                        from: 1; to: 300; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.cornerRegionHeight = value }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Bottom")
                GroupedList {
                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "position_bottom_left"
                        text: Translation.tr("Bottom-left")
                        textRole: "displayName"
                        fieldWidth: 50
                        model: GlobalStates.hotCornerOptions
                        currentValue: Config.options.sidebar.cornerOpen.bottomLeftAction
                        onSelected: newValue => { Config.options.sidebar.cornerOpen.bottomLeftAction = newValue }
                    }
                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "position_bottom_right"
                        text: Translation.tr("Bottom-right")
                        textRole: "displayName"
                        fieldWidth: 55
                        model: GlobalStates.hotCornerOptions
                        currentValue: Config.options.sidebar.cornerOpen.bottomRightAction
                        onSelected: newValue => { Config.options.sidebar.cornerOpen.bottomRightAction = newValue }
                    }
                }
            }
        }

        ContentSection { // I see that for many the overview is important, I put it first why not
            visible: WM.compositor !== "niri"
            icon: "overview_key"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Overview")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.overview.enable
                    onCheckedChanged: {
                        Config.options.overview.enable = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Center icons")
                    checked: Config.options.overview.centerIcons
                    onCheckedChanged: {
                        Config.options.overview.centerIcons = checked;
                    }
                }
                ConfigSpinBox {
                    icon: "loupe"
                    text: Translation.tr("Scale (%)")
                    value: Config.options.overview.scale * 100
                    from: 1
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.overview.scale = value / 100;
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: Config.options.overview.style
                    onSelected: newValue => {
                        Config.options.overview.style = newValue
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "grid_on",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Niri Like"),
                            icon: "mobiledata_arrows",
                            value: "niri"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Default Settings")
                visible: Config.options.overview.style !== "niri"

                GroupedList {
                    visible: Config.options.overview.style !== "niri"
                    ConfigRow {
                        uniform: true
                        visible: Config.options.overview.style !== "niri"
                        ConfigSpinBox {
                            icon: "splitscreen_bottom"
                            text: Translation.tr("Rows")
                            value: Config.options.overview.rows
                            from: 1
                            to: 20
                            stepSize: 1
                            onValueChanged: {
                                Config.options.overview.rows = value;
                            }
                        }
                        ConfigSpinBox {
                            icon: "splitscreen_right"
                            text: Translation.tr("Columns")
                            value: Config.options.overview.columns
                            from: 1
                            to: 20
                            stepSize: 1
                            onValueChanged: {
                                Config.options.overview.columns = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        visible: Config.options.overview.style !== "niri"
                        ConfigSelectionArray {
                            currentValue: Config.options.overview.orderRightLeft
                            onSelected: newValue => {
                                Config.options.overview.orderRightLeft = newValue
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Left to right"),
                                    icon: "arrow_forward",
                                    value: 0
                                },
                                {
                                    displayName: Translation.tr("Right to left"),
                                    icon: "arrow_back",
                                    value: 1
                                }
                            ]
                        }
                        ConfigSelectionArray {
                            currentValue: Config.options.overview.orderBottomUp
                            onSelected: newValue => {
                                Config.options.overview.orderBottomUp = newValue
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Top-down"),
                                    icon: "arrow_downward",
                                    value: 0
                                },
                                {
                                    displayName: Translation.tr("Bottom-up"),
                                    icon: "arrow_upward",
                                    value: 1
                                }
                            ]
                        }
                    }
                }
            }
        }
    }
}
