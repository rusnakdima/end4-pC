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

    // Same roles as the settings panel border color on the Interface page.
    readonly property var borderColorRoles: ["primary", "secondary", "tertiary", "primaryContainer", "secondaryContainer", "tertiaryContainer", "layer0Border"]

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        // Visual & Aesthetics
        ContentSection {
            icon: "deblur"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Visual & Aesthetics")

            GroupedList {
                ConfigSpinBox {
                    icon: "rounded_corner"
                    text: Translation.tr("Window Rounding")
                    value: Config.options.hyprland.decoration.rounding
                    from: 0; to: 30; stepSize: 1
                    onValueChanged: {
                        if (value === Config.options.hyprland.decoration.rounding) return
                        Config.options.hyprland.decoration.rounding = value
                        HyprlandConfig.set("decoration:rounding", value)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur")
                    checked: Config.options.hyprland.decoration.blur.enabled
                    onCheckedChanged: {
                        if (checked === Config.options.hyprland.decoration.blur.enabled) return
                        Config.options.hyprland.decoration.blur.enabled = checked
                        HyprlandConfig.set("decoration:blur:enabled", checked ? 1 : 0)
                    }
                }

                ConfigRow {
                    uniform: true
                    ConfigSpinBox {
                        icon: "blur_circular"
                        text: Translation.tr("Blur Size")
                        value: Config.options.hyprland.decoration.blur.size
                        from: 1; to: 20; stepSize: 1
                        onValueChanged: {
                            if (value === Config.options.hyprland.decoration.blur.size) return
                            Config.options.hyprland.decoration.blur.size = value
                            HyprlandConfig.set("decoration:blur:size", value)
                        }
                    }

                    ConfigSpinBox {
                        icon: "layers"
                        text: Translation.tr("Blur Passes")
                        value: Config.options.hyprland.decoration.blur.passes
                        from: 1; to: 6; stepSize: 1
                        onValueChanged: {
                            if (value === Config.options.hyprland.decoration.blur.passes) return
                            Config.options.hyprland.decoration.blur.passes = value
                            HyprlandConfig.set("decoration:blur:passes", value)
                        }
                    }
                }

                ConfigRow {
                    uniform: true
                    ConfigSpinBox {
                        icon: "margin"
                        text: Translation.tr("Gaps In")
                        value: Config.options.hyprland.general.gapsIn
                        from: 0; to: 40; stepSize: 1
                        onValueChanged: {
                            if (value === Config.options.hyprland.general.gapsIn) return
                            Config.options.hyprland.general.gapsIn = value
                            HyprlandConfig.set("general:gaps_in", value)
                        }
                    }

                    ConfigSpinBox {
                        icon: "open_in_full"
                        text: Translation.tr("Gaps Out")
                        value: Config.options.hyprland.general.gapsOut
                        from: 0; to: 60; stepSize: 1
                        onValueChanged: {
                            if (value === Config.options.hyprland.general.gapsOut) return
                            Config.options.hyprland.general.gapsOut = value
                            HyprlandConfig.set("general:gaps_out", value)
                        }
                    }
                }

                ConfigRow {
                    uniform: true
                    ConfigSpinBox {
                        icon: "opacity"
                        text: Translation.tr("Active Opacity")
                        value: Math.round(Config.options.hyprland.decoration.activeOpacity * 100)
                        from: 10; to: 100; stepSize: 5
                        onValueChanged: {
                            const newVal = value / 100.0
                            if (newVal === Config.options.hyprland.decoration.activeOpacity) return
                            Config.options.hyprland.decoration.activeOpacity = newVal
                            HyprlandConfig.set("decoration:active_opacity", newVal)
                        }
                    }

                    ConfigSpinBox {
                        icon: "opacity"
                        text: Translation.tr("Inactive Opacity")
                        value: Math.round(Config.options.hyprland.decoration.inactiveOpacity * 100)
                        from: 10; to: 100; stepSize: 5
                        onValueChanged: {
                            const newVal = value / 100.0
                            if (newVal === Config.options.hyprland.decoration.inactiveOpacity) return
                            Config.options.hyprland.decoration.inactiveOpacity = newVal
                            HyprlandConfig.set("decoration:inactive_opacity", newVal)
                        }
                    }
                }
                ConfigSpinBox {
                    icon: "border_outer"
                    text: Translation.tr("Border Size")
                    value: Config.options.hyprland.general.borderSize
                    from: 0; to: 10; stepSize: 1
                    onValueChanged: {
                        if (value === Config.options.hyprland.general.borderSize) return
                        Config.options.hyprland.general.borderSize = value
                        HyprlandConfig.set("general:border_size", value)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "format_paint"
                    text: Translation.tr("Custom border colors")
                    checked: Config.options.hyprland.general.borderColor.enable
                    onCheckedChanged: {
                        if (checked === Config.options.hyprland.general.borderColor.enable) return
                        Config.options.hyprland.general.borderColor.enable = checked
                        if (checked) HyprlandConfig.applyBorderColors()
                        else HyprlandConfig.resetBorderColors()
                    }
                }
            }


            ContentSubsection {
                Layout.topMargin: 10
                visible: Config.options.hyprland.general.borderColor.enable
                title: Translation.tr("Border Color Management")
                GroupedList {
                    visible: Config.options.hyprland.general.borderColor.enable

                    ColorSelectionArray {
                        icon: "border_color"
                        text: Translation.tr("Active border")
                        options: page.borderColorRoles
                        currentValue: Config.options.hyprland.general.borderColor.activeRole
                        onSelected: newValue => {
                            Config.options.hyprland.general.borderColor.activeRole = newValue
                            HyprlandConfig.applyBorderColors()
                        }
                    }

                    ConfigSpinBox {
                        icon: "opacity"
                        text: Translation.tr("Active border opacity")
                        value: Math.round(Config.options.hyprland.general.borderColor.activeOpacity * 100)
                        from: 0; to: 100; stepSize: 5
                        onValueChanged: {
                            // Compared as integers: the spin box only holds whole percents.
                            if (value === Math.round(Config.options.hyprland.general.borderColor.activeOpacity * 100)) return
                            Config.options.hyprland.general.borderColor.activeOpacity = value / 100.0
                            HyprlandConfig.applyBorderColors()
                        }
                    }

                    ColorSelectionArray {
                        icon: "border_color"
                        text: Translation.tr("Inactive border")
                        options: page.borderColorRoles
                        currentValue: Config.options.hyprland.general.borderColor.inactiveRole
                        onSelected: newValue => {
                            Config.options.hyprland.general.borderColor.inactiveRole = newValue
                            HyprlandConfig.applyBorderColors()
                        }
                    }

                    ConfigSpinBox {
                        icon: "opacity"
                        text: Translation.tr("Inactive border opacity")
                        value: Math.round(Config.options.hyprland.general.borderColor.inactiveOpacity * 100)
                        from: 0; to: 100; stepSize: 5
                        onValueChanged: {
                            // Compared as integers: the spin box only holds whole percents.
                            if (value === Math.round(Config.options.hyprland.general.borderColor.inactiveOpacity * 100)) return
                            Config.options.hyprland.general.borderColor.inactiveOpacity = value / 100.0
                            HyprlandConfig.applyBorderColors()
                        }
                    }
                }
            }

            ContentSubsection {
                Layout.topMargin: 10
                title: Translation.tr("Shadows, dimming & blur")

                GroupedList {
                    HyprOptionSwitch {
                        optionKey: "decoration:shadow:enabled"
                        buttonIcon: "shadow"
                        text: Translation.tr("Window shadows")
                    }
                    HyprOptionSpinBox {
                        optionKey: "decoration:shadow:range"
                        icon: "blur_on"
                        text: Translation.tr("Shadow range")
                        from: 0; to: 50; stepSize: 1
                    }
                    HyprOptionSwitch {
                        optionKey: "decoration:dim_inactive"
                        buttonIcon: "brightness_low"
                        text: Translation.tr("Dim inactive windows")
                    }
                    HyprOptionSpinBox {
                        optionKey: "decoration:dim_strength"
                        icon: "contrast"
                        text: Translation.tr("Dim strength")
                        factor: 100
                        from: 0; to: 100; stepSize: 5
                    }
                    HyprOptionSpinBox {
                        optionKey: "decoration:blur:noise"
                        icon: "grain"
                        text: Translation.tr("Blur noise")
                        factor: 100
                        from: 0; to: 50; stepSize: 1
                    }
                    HyprOptionSpinBox {
                        optionKey: "decoration:blur:vibrancy"
                        icon: "palette"
                        text: Translation.tr("Blur vibrancy")
                        factor: 100
                        from: 0; to: 100; stepSize: 5
                    }
                }
            }
        }

        // Animations
        ContentSection {
            icon: "animation"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Animations")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.hyprland.animations.enable
                    onCheckedChanged: {
                        if (checked === Config.options.hyprland.animations.enable) return
                        Config.options.hyprland.animations.enable = checked
                        HyprlandConfig.set("animations:enabled", checked ? 1 : 0)
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Presets")
                    icon: "present_to_all"
                    currentValue: Config.options.hyprland.animations.animation
                    onSelected: newValue => {
                        Config.options.hyprland.animations.animation = newValue
                        saveAnimProc.command = [
                            "python3",
                            HyprlandConfig.configuratorScriptPath,
                            "--anim-preset", newValue
                        ]
                        saveAnimProc.running = true
                    }
                    options: [
                        { displayName: Translation.tr("Elastic"),   icon: "move_selection_right", value: "fast"   },
                        { displayName: Translation.tr("Normal"),    icon: "animation",            value: "normal" },
                        { displayName: Translation.tr("Niri Like"), icon: "mobiledata_arrows",    value: "niri"   },
                    ]
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                Layout.topMargin: 15
                text: Translation.tr("Animation presets require a require line in your hyprland.lua. Add the following line to enable presets:") + '\n\nrequire("hyprland/shellOverrides/animations")'

                Item { Layout.fillWidth: true }

                RippleButtonWithIcon {
                    id: copySourceButton
                    property bool justCopied: false
                    Layout.fillWidth: false
                    buttonRadius: Appearance.rounding.small
                    materialIcon: justCopied ? "check" : "content_copy"
                    mainText: justCopied ? Translation.tr("Copied!") : Translation.tr("Copy line")
                    onClicked: {
                        copySourceButton.justCopied = true
                        Quickshell.clipboardText = 'require("hyprland/shellOverrides/animations")'
                        revertSourceTimer.restart()
                    }
                    colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    Timer {
                        id: revertSourceTimer
                        interval: 1500
                        onTriggered: copySourceButton.justCopied = false
                    }
                }
            }

            Process {
                id: saveAnimProc
                onRunningChanged: if (!running) reloadAnimProc.running = true
            }
            Process {
                id: reloadAnimProc
                command: ["hyprctl", "reload"]
            }
        }
    }
}
