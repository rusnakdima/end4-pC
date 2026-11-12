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

        // Idle
        ContentSection {
            id: idleSection
            icon: "timer"
            shape: MaterialShape.Shape.Cookie12Sided
            title: Translation.tr("Idle")

            readonly property list<var> unitOptions: [
                { displayName: Translation.tr("Seconds"), icon: "timer",    value: 1    },
                { displayName: Translation.tr("Minutes"), icon: "av_timer", value: 60   },
                { displayName: Translation.tr("Hours"),   icon: "schedule", value: 3600 },
                { displayName: Translation.tr("Never"),   icon: "block",    value: 0    },
            ]

            component IdleTimerRow: ConfigRow {
                id: timerRow

                property string icon
                property string label
                property int seconds: 0
                property int displayValue: 0
                property int displayUnit: 0
                property bool loaded: false

                signal edited(int newSeconds)

                onSecondsChanged: {
                    const display = HyprlandConfig.idleDisplay(timerRow.seconds)
                    timerRow.displayValue = display[0]
                    timerRow.displayUnit = display[1]
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Layout.leftMargin: 8
                    OptionalMaterialSymbol {
                        icon: timerRow.icon
                        iconSize: Appearance.font.pixelSize.larger
                    }
                    StyledText {
                        Layout.preferredWidth: 160
                        text: timerRow.label
                        color: Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                    }
                    Item { Layout.fillWidth: true }
                    StyledSpinBox {
                        Layout.preferredWidth: 130
                        enabled: timerRow.displayUnit !== 0
                        value: timerRow.displayValue
                        from: 0
                        to: 9999
                        stepSize: 1
                        onValueChanged: {
                            if (!timerRow.loaded) return
                            timerRow.displayValue = value
                            timerRow.edited(HyprlandConfig.idleSeconds(value, timerRow.displayUnit))
                        }
                    }
                }
                StyledComboBox {
                    Layout.preferredWidth: 140
                    Layout.alignment: Qt.AlignVCenter
                    textRole: "displayName"
                    model: idleSection.unitOptions
                    currentIndex: idleSection.unitOptions.findIndex(o => o.value === timerRow.displayUnit)
                    onActivated: index => {
                        timerRow.displayUnit = idleSection.unitOptions[index].value
                        timerRow.edited(HyprlandConfig.idleSeconds(timerRow.displayValue, timerRow.displayUnit))
                    }
                }
            }

            function applyIdle() {
                HyprlandConfig.setIdle(
                    Config.options.hyprland.idle.lock,
                    Config.options.hyprland.idle.screenOff,
                    Config.options.hyprland.idle.suspend
                )
            }

            GroupedList {
                IdleTimerRow {
                    icon: "lock_clock"
                    label: Translation.tr("Lock screen")
                    seconds: Config.options.hyprland.idle.lock
                    onEdited: newSeconds => {
                        Config.options.hyprland.idle.lock = newSeconds
                        idleSection.applyIdle()
                    }
                    Component.onCompleted: loaded = true
                }
                IdleTimerRow {
                    icon: "monitor"
                    label: Translation.tr("Screen off")
                    seconds: Config.options.hyprland.idle.screenOff
                    onEdited: newSeconds => {
                        Config.options.hyprland.idle.screenOff = newSeconds
                        idleSection.applyIdle()
                    }
                    Component.onCompleted: loaded = true
                }
                IdleTimerRow {
                    icon: "bedtime"
                    label: Translation.tr("Standby")
                    seconds: Config.options.hyprland.idle.suspend
                    onEdited: newSeconds => {
                        Config.options.hyprland.idle.suspend = newSeconds
                        idleSection.applyIdle()
                    }
                    Component.onCompleted: loaded = true
                }
            }
        }

        // Misc
        ContentSection {
            icon: "tune"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Misc")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Focus on activate")
                    checked: Config.options.hyprland.misc.focusOnActivate
                    onCheckedChanged: {
                        if (checked === Config.options.hyprland.misc.focusOnActivate) return
                        Config.options.hyprland.misc.focusOnActivate = checked
                        HyprlandConfig.set("misc:focus_on_activate", checked ? 1 : 0)
                    }
                }
                    HyprOptionSelection {
                        optionKey: "misc:vrr"
                        icon: "slow_motion_video"
                        text: Translation.tr("Variable refresh rate (VRR)")
                        fallback: 0
                        options: [
                            { displayName: Translation.tr("Off"), icon: "block", value: 0 },
                            { displayName: Translation.tr("On"), icon: "check_circle", value: 1 },
                            { displayName: Translation.tr("Fullscreen only"), icon: "fullscreen", value: 2 }
                        ]
                    }
                    HyprOptionSwitch {
                        optionKey: "misc:enable_swallow"
                        buttonIcon: "call_merge"
                        text: Translation.tr("Window swallowing (terminal swallows launched apps)")
                    }
                    HyprOptionSwitch {
                        optionKey: "misc:animate_manual_resizes"
                        buttonIcon: "animation"
                        text: Translation.tr("Animate manual resizes")
                    }
                    HyprOptionSwitch {
                        optionKey: "misc:close_special_on_empty"
                        buttonIcon: "close_fullscreen"
                        text: Translation.tr("Close empty special workspace")
                    }
                    HyprOptionSwitch {
                        optionKey: "misc:disable_hyprland_logo"
                        buttonIcon: "hide_image"
                        text: Translation.tr("Hide the Hyprland logo")
                    }
                    HyprOptionSwitch {
                        optionKey: "misc:disable_splash_rendering"
                        buttonIcon: "subtitles_off"
                        text: Translation.tr("Hide the splash text")
                    }
                    HyprOptionSwitch {
                        optionKey: "misc:mouse_move_enables_dpms"
                        buttonIcon: "mouse"
                        text: Translation.tr("Mouse wakes the screen")
                    }
                    HyprOptionSwitch {
                        optionKey: "misc:key_press_enables_dpms"
                        buttonIcon: "keyboard"
                        text: Translation.tr("Keys wake the screen")
                    }
                    HyprOptionSwitch {
                        optionKey: "xwayland:force_zero_scaling"
                        buttonIcon: "zoom_out_map"
                        text: Translation.tr("XWayland: sharp apps (force zero scaling)")
                    }
                    HyprOptionSwitch {
                        optionKey: "group:auto_group"
                        buttonIcon: "tab_group"
                        text: Translation.tr("Auto-group dragged windows")
                    }
                    HyprOptionSwitch {
                        optionKey: "binds:workspace_back_and_forth"
                        buttonIcon: "swap_horiz"
                        text: Translation.tr("Switching to the current workspace goes back")
                    }
                    HyprOptionSwitch {
                        optionKey: "binds:allow_workspace_cycles"
                        buttonIcon: "cached"
                        text: Translation.tr("Allow workspace cycles")
                    }
                    HyprOptionSelection {
                        optionKey: "render:direct_scanout"
                        icon: "speed"
                        text: Translation.tr("Direct scanout (fullscreen apps)")
                        fallback: 0
                        options: [
                            { displayName: Translation.tr("Off"), icon: "block", value: 0 },
                            { displayName: Translation.tr("On"), icon: "check_circle", value: 1 },
                            { displayName: Translation.tr("Auto"), icon: "auto_mode", value: 2 }
                        ]
                    }
            }
        }
    }
}
