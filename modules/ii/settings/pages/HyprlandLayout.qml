import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import qs.modules.common.functions
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.hyprland

ContentPage {
    id: page
    forceWidth: true

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        // Layout
        ContentSection {
            icon: "auto_awesome_mosaic"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Layout")

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Window mode")
                    icon: "select_window"
                    currentValue: WindowMode.mode
                    onSelected: newValue => WindowMode.setMode(newValue)
                    options: [
                        { displayName: Translation.tr("Tiling"),   icon: "grid_view", value: "tiling"   },
                        { displayName: Translation.tr("Stacking"), icon: "layers",    value: "stacking" },
                    ]
                }
            }

            GroupedList {
                visible: WindowMode.mode === "tiling"
                ConfigSelectionArray {
                    text: Translation.tr("Tiling Layout")
                    icon: "responsive_layout"
                    currentValue: Config.options.hyprland.general.layout
                    onSelected: newValue => {
                        Config.options.hyprland.general.layout = newValue
                        HyprlandConfig.set("general:layout", newValue)
                    }
                    options: [
                        { displayName: Translation.tr("Dwindle"),   icon: "browse",             value: "dwindle"   },
                        { displayName: Translation.tr("Master"),    icon: "auto_awesome_mosaic", value: "master"    },
                        { displayName: Translation.tr("Scrolling"), icon: "view_carousel",       value: "scrolling" },
                    ]
                }
            }

            ContentSubsection {
                Layout.topMargin: 10
                visible: Config.options.hyprland.general.layout === "dwindle"
                title: Translation.tr("Dwindle")

                GroupedList {
                    HyprOptionSwitch {
                        optionKey: "dwindle:preserve_split"
                        buttonIcon: "call_split"
                        text: Translation.tr("Preserve split direction")
                    }
                    HyprOptionSwitch {
                        optionKey: "dwindle:smart_split"
                        buttonIcon: "smart_toy"
                        text: Translation.tr("Smart split (follow the cursor)")
                    }
                    HyprOptionSelection {
                        optionKey: "dwindle:force_split"
                        icon: "splitscreen"
                        text: Translation.tr("Force split side")
                        fallback: 0
                        options: [
                            { displayName: Translation.tr("Auto"), icon: "auto_mode", value: 0 },
                            { displayName: Translation.tr("Left / top"), icon: "align_horizontal_left", value: 1 },
                            { displayName: Translation.tr("Right / bottom"), icon: "align_horizontal_right", value: 2 }
                        ]
                    }
                    HyprOptionSpinBox {
                        optionKey: "dwindle:default_split_ratio"
                        icon: "percent"
                        text: Translation.tr("Default split ratio")
                        factor: 10
                        from: 2; to: 18; stepSize: 1
                    }
                }
            }

            ContentSubsection {
                Layout.topMargin: 10
                visible: Config.options.hyprland.general.layout === "master"
                title: Translation.tr("Master")

                GroupedList {
                    HyprOptionSelection {
                        optionKey: "master:new_status"
                        icon: "add_box"
                        text: Translation.tr("New windows become")
                        fallback: "slave"
                        options: [
                            { displayName: Translation.tr("Master"), icon: "star", value: "master" },
                            { displayName: Translation.tr("Slave"), icon: "view_agenda", value: "slave" },
                            { displayName: Translation.tr("Inherit"), icon: "content_copy", value: "inherit" }
                        ]
                    }
                    HyprOptionSelection {
                        optionKey: "master:orientation"
                        icon: "screen_rotation"
                        text: Translation.tr("Master position")
                        fallback: "left"
                        options: [
                            { displayName: Translation.tr("Left"), icon: "align_horizontal_left", value: "left" },
                            { displayName: Translation.tr("Right"), icon: "align_horizontal_right", value: "right" },
                            { displayName: Translation.tr("Top"), icon: "align_vertical_top", value: "top" },
                            { displayName: Translation.tr("Bottom"), icon: "align_vertical_bottom", value: "bottom" },
                            { displayName: Translation.tr("Center"), icon: "align_horizontal_center", value: "center" }
                        ]
                    }
                    HyprOptionSpinBox {
                        optionKey: "master:mfact"
                        icon: "aspect_ratio"
                        text: Translation.tr("Master size")
                        factor: 100
                        from: 10; to: 90; stepSize: 5
                    }
                }
            }

            ContentSubsection {
                Layout.topMargin: 10
                title: Translation.tr("App window rules")

                AppWindowRules {}
            }
        }

        // Windows
        ContentSection {
            icon: "select_window"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("Windows")

            GroupedList {
                HyprOptionSwitch {
                    optionKey: "general:resize_on_border"
                    buttonIcon: "open_in_full"
                    text: Translation.tr("Resize windows by dragging their borders")
                }
                HyprOptionSpinBox {
                    optionKey: "general:extend_border_grab_area"
                    icon: "border_outer"
                    text: Translation.tr("Border grab area (px)")
                    from: 0; to: 60; stepSize: 1
                }
                HyprOptionSwitch {
                    optionKey: "general:allow_tearing"
                    buttonIcon: "sports_esports"
                    text: Translation.tr("Allow tearing (lower latency in games)")
                }
            }
        }
    }
}
