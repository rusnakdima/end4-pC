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

        // Input
        ContentSection {
            icon: "trackpad_input"
            shape: MaterialShape.Shape.Pentagon
            title: Translation.tr("Input")

            ContentSubsection {
                title: Translation.tr("Keyboard")

                GroupedList {
                    ConfigMultiSelect {
                        Layout.fillWidth: true
                        buttonIcon: "keyboard"
                        text: Translation.tr("Keyboard layout")
                        description: Translation.tr("Each chip is one layout; the first one is the active layout")
                        model: XkbRules.layouts
                        value: Config.options.hyprland.input.kbLayout
                        onEdited: newValue => {
                            Config.options.hyprland.input.kbLayout = newValue;
                            HyprlandConfig.set("input:kb_layout", newValue);
                            // The nth variant belongs to the nth layout, so
                            // changing the layouts can invalidate slots.
                            const variant = String(HyprlandOptions.get("input:kb_variant", ""));
                            const clean = XkbRules.sanitizeVariant(variant, newValue);
                            if (clean !== variant) HyprlandOptions.apply("input:kb_variant", clean);
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "numbers"
                        text: Translation.tr("Numlock by default")
                        checked: Config.options.hyprland.input.numlock
                        onCheckedChanged: {
                            if (checked === Config.options.hyprland.input.numlock) return
                            Config.options.hyprland.input.numlock = checked
                            HyprlandConfig.set("input:numlock_by_default", checked ? 1 : 0)
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigSpinBox {
                            icon: "keyboard_return"
                            text: Translation.tr("Repeat delay (ms)")
                            value: Config.options.hyprland.input.repeatDelay
                            from: 100; to: 1000; stepSize: 10
                            onValueChanged: {
                                if (value === Config.options.hyprland.input.repeatDelay) return
                                Config.options.hyprland.input.repeatDelay = value
                                HyprlandConfig.set("input:repeat_delay", value)
                            }
                        }

                        ConfigSpinBox {
                            icon: "speed"
                            text: Translation.tr("Repeat rate")
                            value: Config.options.hyprland.input.repeatRate
                            from: 10; to: 100; stepSize: 1
                            onValueChanged: {
                                if (value === Config.options.hyprland.input.repeatRate) return
                                Config.options.hyprland.input.repeatRate = value
                                HyprlandConfig.set("input:repeat_rate", value)
                            }
                        }
                    }
                    ConfigMultiSelect {
                        Layout.fillWidth: true
                        positional: true
                        buttonIcon: "keyboard_alt"
                        text: Translation.tr("Keyboard variant")
                        description: Translation.tr("One chip per layout, in order — the nth variant belongs to the nth layout")
                        model: XkbRules.variantEntries(Config.options.hyprland.input.kbLayout)
                        value: XkbRules.sanitizeVariant(String(HyprlandOptions.get("input:kb_variant", "")), Config.options.hyprland.input.kbLayout)
                        onEdited: newValue => HyprlandOptions.apply("input:kb_variant", newValue)
                    }
                    ConfigMultiSelect {
                        Layout.fillWidth: true
                        buttonIcon: "keyboard_command_key"
                        text: Translation.tr("Keyboard options")
                        model: XkbRules.options
                        value: String(HyprlandOptions.get("input:kb_options", ""))
                        onEdited: newValue => HyprlandOptions.apply("input:kb_options", newValue)
                    }
                    ConfigSelectionArray {
                        text: Translation.tr("Follow mouse")
                        icon: "mouse"
                        currentValue: Config.options.hyprland.input.followMouse
                        onSelected: newValue => {
                            Config.options.hyprland.input.followMouse = newValue
                            HyprlandConfig.set("input:follow_mouse", newValue)
                        }
                        options: [
                            { displayName: Translation.tr("Disabled"), icon: "mouse",     value: 0 },
                            { displayName: Translation.tr("Full"),     icon: "open_with",  value: 1 },
                            { displayName: Translation.tr("Loose"),    icon: "drag_pan",   value: 2 },
                            { displayName: Translation.tr("Explicit"), icon: "ads_click",  value: 3 },
                        ]
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Mouse")

                GroupedList {
                    HyprOptionSpinBox {
                        optionKey: "input:sensitivity"
                        icon: "speed"
                        text: Translation.tr("Pointer sensitivity")
                        factor: 10
                        from: -10; to: 10; stepSize: 1
                    }
                    HyprOptionSelection {
                        optionKey: "input:accel_profile"
                        icon: "trending_up"
                        text: Translation.tr("Acceleration profile")
                        fallback: ""
                        options: [
                            { displayName: Translation.tr("Default"), icon: "settings_backup_restore", value: "" },
                            { displayName: Translation.tr("Flat"), icon: "horizontal_rule", value: "flat" },
                            { displayName: Translation.tr("Adaptive"), icon: "show_chart", value: "adaptive" }
                        ]
                    }
                    HyprOptionSwitch {
                        optionKey: "input:force_no_accel"
                        buttonIcon: "mouse"
                        text: Translation.tr("Disable acceleration (raw input)")
                    }
                    HyprOptionSwitch {
                        optionKey: "input:left_handed"
                        buttonIcon: "front_hand"
                        text: Translation.tr("Left-handed buttons")
                    }
                    HyprOptionSwitch {
                        optionKey: "misc:middle_click_paste"
                        buttonIcon: "content_paste"
                        text: Translation.tr("Middle click paste")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Touchpad")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Natural scroll")
                        checked: Config.options.hyprland.input.touchpad.naturalScroll
                        onCheckedChanged: {
                            if (checked === Config.options.hyprland.input.touchpad.naturalScroll) return
                            Config.options.hyprland.input.touchpad.naturalScroll = checked
                            HyprlandConfig.set("input:touchpad:natural_scroll", checked ? 1 : 0)
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "keyboard_hide"
                        text: Translation.tr("Disable while typing")
                        checked: Config.options.hyprland.input.touchpad.disableWhileTyping
                        onCheckedChanged: {
                            if (checked === Config.options.hyprland.input.touchpad.disableWhileTyping) return
                            Config.options.hyprland.input.touchpad.disableWhileTyping = checked
                            HyprlandConfig.set("input:touchpad:disable_while_typing", checked ? 1 : 0)
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "touch_app"
                        text: Translation.tr("Clickfinger behavior")
                        checked: Config.options.hyprland.input.touchpad.clickfingerBehavior
                        onCheckedChanged: {
                            if (checked === Config.options.hyprland.input.touchpad.clickfingerBehavior) return
                            Config.options.hyprland.input.touchpad.clickfingerBehavior = checked
                            HyprlandConfig.set("input:touchpad:clickfinger_behavior", checked ? 1 : 0)
                        }
                    }

                    HyprOptionSwitch {
                        optionKey: "input:touchpad:tap-to-click"
                        buttonIcon: "touch_app"
                        text: Translation.tr("Tap to click")
                    }
                    HyprOptionSwitch {
                        optionKey: "input:touchpad:tap-and-drag"
                        buttonIcon: "drag_pan"
                        text: Translation.tr("Tap and drag")
                    }
                    HyprOptionSwitch {
                        optionKey: "input:touchpad:middle_button_emulation"
                        buttonIcon: "mouse"
                        text: Translation.tr("Middle button emulation (3-finger tap)")
                    }
                    ConfigSpinBox {
                        icon: "swipe"
                        text: Translation.tr("Scroll factor")
                        value: Math.round(Config.options.hyprland.input.touchpad.scrollFactor * 10)
                        from: 1; to: 30; stepSize: 1
                        onValueChanged: {
                            const newVal = value / 10.0
                            if (newVal === Config.options.hyprland.input.touchpad.scrollFactor) return
                            Config.options.hyprland.input.touchpad.scrollFactor = newVal
                            HyprlandConfig.set("input:touchpad:scroll_factor", newVal)
                        }
                    }
                }
            }
        }

        // Cursor
        ContentSection {
            icon: "mouse"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("Cursor")

            GroupedList {
                HyprOptionSelection {
                    optionKey: "cursor:no_hardware_cursors"
                    icon: "mouse"
                    text: Translation.tr("Hardware cursor")
                    fallback: 2
                    options: [
                        { displayName: Translation.tr("Auto"), icon: "auto_mode", value: 2 },
                        { displayName: Translation.tr("On"), icon: "check_circle", value: 0 },
                        { displayName: Translation.tr("Off"), icon: "block", value: 1 }
                    ]
                }
                HyprOptionSpinBox {
                    optionKey: "cursor:inactive_timeout"
                    icon: "hourglass_empty"
                    text: Translation.tr("Hide cursor after inactivity (s, 0 = never)")
                    from: 0; to: 60; stepSize: 1
                }
                HyprOptionSwitch {
                    optionKey: "cursor:hide_on_key_press"
                    buttonIcon: "keyboard_hide"
                    text: Translation.tr("Hide cursor while typing")
                }
                HyprOptionSelection {
                    optionKey: "cursor:warp_on_change_workspace"
                    icon: "ads_click"
                    text: Translation.tr("Move cursor to the new workspace")
                    fallback: 0
                    options: [
                        { displayName: Translation.tr("Off"), icon: "block", value: 0 },
                        { displayName: Translation.tr("On"), icon: "check_circle", value: 1 },
                        { displayName: Translation.tr("Force"), icon: "bolt", value: 2 }
                    ]
                }
            }
        }
    }
}
