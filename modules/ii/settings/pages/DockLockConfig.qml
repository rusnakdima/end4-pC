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
            icon: "call_to_action"
            title: Translation.tr("Dock")
            shape: MaterialShape.Shape.Cookie6Sided

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.dock.enable
                    onCheckedChanged: { Config.options.dock.enable = checked }
                }
                ConfigSwitch {
                    buttonIcon: "background_dot_small"
                    text: Translation.tr("Background")
                    checked: Config.options.dock.showBackground
                    onCheckedChanged: { Config.options.dock.showBackground = checked }
                }
                ConfigSwitch {
                    buttonIcon: "highlight_mouse_cursor"
                    text: Translation.tr("Hover to reveal")
                    checked: Config.options.dock.hoverToReveal
                    onCheckedChanged: { Config.options.dock.hoverToReveal = checked }
                }
                ConfigSwitch {
                    buttonIcon: "push_pin"
                    text: Translation.tr("Pinned on startup")
                    checked: Config.options.dock.pinnedOnStartup
                    onCheckedChanged: { Config.options.dock.pinnedOnStartup = checked }
                }
            }

            ContentSubsection {
                title: Translation.tr("Appearance")
                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Style")
                        icon: "dock_to_bottom"
                        currentValue: Config.options.dock.style
                        onSelected: newValue => { Config.options.dock.style = newValue }
                        options: [
                            { displayName: Translation.tr("Float"), icon: "call_to_action", value: "float" },
                            { displayName: Translation.tr("Hug"), icon: "dock_to_bottom", value: "hug" }
                        ]
                    }
                    ConfigSwitch {
                        buttonIcon: "zoom_in"
                        text: Translation.tr("Magnification")
                        checked: Config.options.dock.magnify
                        onCheckedChanged: { Config.options.dock.magnify = checked }
                    }
                    ConfigSpinBox {
                        visible: Config.options.dock.magnify
                        icon: "zoom_out_map"
                        text: Translation.tr("Magnification amount (%)")
                        value: Config.options.dock.magnification * 100
                        from: 110
                        to: 220
                        stepSize: 10
                        onValueChanged: { Config.options.dock.magnification = value / 100 }
                    }
                    ConfigSelectionArray {
                        text: Translation.tr("Position")
                        icon: "dock_to_bottom"
                        currentValue: Config.options.dock.position
                        onSelected: newValue => { Config.options.dock.position = newValue }
                        options: [
                            { displayName: Translation.tr("Left"), icon: "dock_to_left", value: "left" },
                            { displayName: Translation.tr("Bottom"), icon: "dock_to_bottom", value: "bottom" },
                            { displayName: Translation.tr("Right"), icon: "dock_to_right", value: "right" }
                        ]
                    }
                    ConfigSpinBox {
                        icon: "rounded_corner"
                        text: Translation.tr("Corner radius")
                        value: Config.options.dock.radius
                        from: 0
                        to: 40
                        stepSize: 1
                        onValueChanged: { Config.options.dock.radius = value }
                    }
                    ColorSelectionArray {
                        icon: "format_paint"
                        text: Translation.tr("Background color")
                        options: ["layer0", "layer1", "primaryContainer", "secondaryContainer", "tertiaryContainer", "primary", "secondary", "tertiary"]
                        currentValue: Config.options.dock.backgroundColor
                        onSelected: newValue => { Config.options.dock.backgroundColor = newValue }
                    }
                    ConfigSwitch {
                        enabled: Config.options.dock.style === "hug"
                        buttonIcon: "filter_frames"
                        text: Translation.tr("Follow frame color")
                        checked: Config.options.dock.followFrameColor
                        onCheckedChanged: { Config.options.dock.followFrameColor = checked }
                    }
                    ConfigSwitch {
                        enabled: Config.options.dock.style !== "hug"
                        buttonIcon: "border_style"
                        text: Translation.tr("Border")
                        checked: Config.options.dock.showBorder
                        onCheckedChanged: { Config.options.dock.showBorder = checked }
                    }
                    ConfigSpinBox {
                        enabled: Config.options.dock.showBorder && Config.options.dock.style !== "hug"
                        icon: "line_weight"
                        text: Translation.tr("Border width")
                        value: Config.options.dock.borderWidth
                        from: 1
                        to: 10
                        stepSize: 1
                        onValueChanged: { Config.options.dock.borderWidth = value }
                    }
                    ColorSelectionArray {
                        enabled: Config.options.dock.showBorder && Config.options.dock.style !== "hug"
                        icon: "format_paint"
                        text: Translation.tr("Border color")
                        options: ["layer0Border", "primary", "secondary", "tertiary", "primaryContainer", "secondaryContainer", "tertiaryContainer", "layer1"]
                        currentValue: Config.options.dock.borderColor
                        onSelected: newValue => { Config.options.dock.borderColor = newValue }
                    }
                }
            }


            ContentSubsection {
                title: Translation.tr("Icons")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "preview"
                        text: Translation.tr("Window previews")
                        checked: Config.options.dock.showPreviews
                        onCheckedChanged: { Config.options.dock.showPreviews = checked }
                    }
                    ConfigSpinBox {
                        icon: "photo_size_select_large"
                        text: Translation.tr("Icon size")
                        value: Config.options.dock.iconSize
                        from: 20
                        to: 48
                        stepSize: 1
                        onValueChanged: { Config.options.dock.iconSize = value }
                    }
                    ConfigSpinBox {
                        icon: "space_bar"
                        text: Translation.tr("Icon spacing")
                        value: Config.options.dock.iconSpacing
                        from: 0
                        to: 12
                        stepSize: 1
                        onValueChanged: { Config.options.dock.iconSpacing = value }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Buttons & Media")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "music_note"
                        text: Translation.tr("Media Player")
                        checked: Config.options.dock.showMedia
                        onCheckedChanged: { Config.options.dock.showMedia = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "keep"
                        text: Translation.tr("Show Pin Button")
                        checked: Config.options.dock.showPinButton
                        onCheckedChanged: { Config.options.dock.showPinButton = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "apps"
                        text: Translation.tr("Show Apps Button")
                        checked: Config.options.dock.showAppsButton
                        onCheckedChanged: { Config.options.dock.showAppsButton = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "colors"
                        text: Translation.tr("Tint app icons")
                        checked: Config.options.dock.monochromeIcons
                        onCheckedChanged: { Config.options.dock.monochromeIcons = checked }
                    }
                }
            }
        }

        ContentSection {
            icon: "lock"
            title: Translation.tr("Lock screen")
            shape: MaterialShape.Shape.Pentagon

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "water_drop"
                    text: Translation.tr("Use Hyprlock (instead of Quickshell)")
                    checked: Config.options.lock.useHyprlock
                    onCheckedChanged: { Config.options.lock.useHyprlock = checked }
                }
                ConfigSwitch {
                    buttonIcon: "account_circle"
                    text: Translation.tr("Launch on startup")
                    checked: Config.options.lock.launchOnStartup
                    onCheckedChanged: { Config.options.lock.launchOnStartup = checked }
                }
                ConfigSwitch {
                    buttonIcon: "widgets"
                    enabled: WM.compositor !== "niri"
                    text: Translation.tr("Show Widgets")
                    checked: Config.options.lock.showWidgets
                    onCheckedChanged: { Config.options.lock.showWidgets = checked }
                }
                ConfigSwitch {
                    buttonIcon: "tools_installation_kit"
                    text: Translation.tr("Show Toolbars")
                    checked: Config.options.lock.showToolbars
                    onCheckedChanged: { Config.options.lock.showToolbars = checked }
                }
                ConfigSwitch {
                    buttonIcon: "music_note"
                    enabled: Config.options.lock.showToolbars
                    text: Translation.tr("Show media player info")
                    checked: Config.options.lock.showMedia
                    onCheckedChanged: { Config.options.lock.showMedia = checked }
                }
            }

            ContentSubsection {
                title: Translation.tr("Security")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "settings_power"
                        text: Translation.tr("Require password to power off/restart")
                        checked: Config.options.lock.security.requirePasswordToPower
                        onCheckedChanged: { Config.options.lock.security.requirePasswordToPower = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "key_vertical"
                        text: Translation.tr("Also unlock keyring")
                        checked: Config.options.lock.security.unlockKeyring
                        onCheckedChanged: { Config.options.lock.security.unlockKeyring = checked }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Style: General")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "center_focus_weak"
                        text: Translation.tr("Center clock")
                        checked: Config.options.lock.centerClock
                        onCheckedChanged: { Config.options.lock.centerClock = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "info"
                        text: Translation.tr('Show "Locked" text')
                        checked: Config.options.lock.showLockedText
                        onCheckedChanged: { Config.options.lock.showLockedText = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "shapes"
                        text: Translation.tr("Use varying shapes for password characters")
                        checked: Config.options.lock.materialShapeChars
                        onCheckedChanged: { Config.options.lock.materialShapeChars = checked }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Style: Blurred")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "blur_on"
                        text: Translation.tr("Enable blur")
                        checked: Config.options.lock.blur.enable
                        onCheckedChanged: { Config.options.lock.blur.enable = checked }
                    }
                    ConfigSpinBox {
                        icon: "deblur"
                        text: Translation.tr("Samples")
                        value: Config.options.lock.blur.size
                        from: 20; to: 200; stepSize: 10
                        onValueChanged: { Config.options.lock.blur.size = value }
                    }
                    ConfigSpinBox {
                        icon: "loupe"
                        text: Translation.tr("Extra wallpaper zoom (%)")
                        value: Config.options.lock.blur.extraZoom * 100
                        from: 1; to: 150; stepSize: 2
                        onValueChanged: { Config.options.lock.blur.extraZoom = value / 100 }
                    }
                }
            }
        }
    }
}
