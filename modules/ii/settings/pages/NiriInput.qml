import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import qs.modules.common.functions
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.niri

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
                    ConfigTextArea {
                        id: kbLayoutField
                        Layout.fillWidth: true
                        buttonIcon: "keyboard"
                        text: Translation.tr("Keyboard layout")
                        placeholderText: Translation.tr("e.g., us, es, latam")
                        Component.onCompleted: value = NiriConfig.options.input.kbLayout
                        onValueChanged: kbLayoutDebounceTimer.restart()

                        Timer {
                            id: kbLayoutDebounceTimer
                            interval: 1000
                            repeat: false
                            onTriggered: {
                                NiriConfig.options.input.kbLayout = kbLayoutField.value
                            }
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "numbers"
                        text: Translation.tr("Numlock by default")
                        checked: NiriConfig.options.input.numlock
                        onCheckedChanged: {
                            if (checked === NiriConfig.options.input.numlock) return
                            NiriConfig.options.input.numlock = checked
                        }
                    }

                    ConfigSpinBox {
                        icon: "keyboard_return"
                        text: Translation.tr("Repeat delay (ms)")
                        value: NiriConfig.options.input.repeatDelay
                        from: 100; to: 1000; stepSize: 10
                        onValueChanged: {
                            if (value === NiriConfig.options.input.repeatDelay) return
                            NiriConfig.options.input.repeatDelay = value
                        }
                    }

                    ConfigSpinBox {
                        icon: "speed"
                        text: Translation.tr("Repeat rate")
                        value: NiriConfig.options.input.repeatRate
                        from: 10; to: 100; stepSize: 1
                        onValueChanged: {
                            if (value === NiriConfig.options.input.repeatRate) return
                            NiriConfig.options.input.repeatRate = value
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "mouse"
                        text: Translation.tr("Focus follows mouse")
                        checked: NiriConfig.options.input.focusFollowsMouse
                        onCheckedChanged: {
                            if (checked === NiriConfig.options.input.focusFollowsMouse) return
                            NiriConfig.options.input.focusFollowsMouse = checked
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Touchpad")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "touch_app"
                        text: Translation.tr("Tap to click")
                        checked: NiriConfig.options.input.touchpad.tap
                        onCheckedChanged: {
                            if (checked === NiriConfig.options.input.touchpad.tap) return
                            NiriConfig.options.input.touchpad.tap = checked
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Natural scroll")
                        checked: NiriConfig.options.input.touchpad.naturalScroll
                        onCheckedChanged: {
                            if (checked === NiriConfig.options.input.touchpad.naturalScroll) return
                            NiriConfig.options.input.touchpad.naturalScroll = checked
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "keyboard_hide"
                        text: Translation.tr("Disable while typing")
                        checked: NiriConfig.options.input.touchpad.disableWhileTyping
                        onCheckedChanged: {
                            if (checked === NiriConfig.options.input.touchpad.disableWhileTyping) return
                            NiriConfig.options.input.touchpad.disableWhileTyping = checked
                        }
                    }

                    ConfigSpinBox {
                        icon: "swipe"
                        text: Translation.tr("Scroll factor")
                        value: Math.round(NiriConfig.options.input.touchpad.scrollFactor * 10)
                        from: 1; to: 30; stepSize: 1
                        onValueChanged: {
                            const newVal = value / 10.0
                            if (newVal === NiriConfig.options.input.touchpad.scrollFactor) return
                            NiriConfig.options.input.touchpad.scrollFactor = newVal
                        }
                    }

                    ConfigSpinBox {
                        icon: "speed"
                        text: Translation.tr("Acceleration speed")
                        value: Math.round(NiriConfig.options.input.touchpad.accelSpeed * 10)
                        from: -10; to: 10; stepSize: 1
                        onValueChanged: {
                            const newVal = value / 10.0
                            if (newVal === NiriConfig.options.input.touchpad.accelSpeed) return
                            NiriConfig.options.input.touchpad.accelSpeed = newVal
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Mouse")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Natural scroll")
                        checked: NiriConfig.options.input.mouse.naturalScroll
                        onCheckedChanged: {
                            if (checked === NiriConfig.options.input.mouse.naturalScroll) return
                            NiriConfig.options.input.mouse.naturalScroll = checked
                        }
                    }

                    ConfigSpinBox {
                        icon: "speed"
                        text: Translation.tr("Acceleration speed")
                        value: Math.round(NiriConfig.options.input.mouse.accelSpeed * 10)
                        from: -10; to: 10; stepSize: 1
                        onValueChanged: {
                            const newVal = value / 10.0
                            if (newVal === NiriConfig.options.input.mouse.accelSpeed) return
                            NiriConfig.options.input.mouse.accelSpeed = newVal
                        }
                    }
                }
            }
        }

        // Cursor
        ContentSection {
            icon: "mouse"
            shape: MaterialShape.Shape.Arrow
            title: Translation.tr("Cursor")
            GroupedList {
                ConfigComboBox {
                    buttonIcon: "mouse"
                    fieldWidth: 70
                    text: Translation.tr("Cursor theme")
                    model: [{ displayName: Translation.tr("Default"), value: "" }]
                        .concat(SystemTheming.cursorThemes.map(t => ({ displayName: t, value: t })))
                    currentValue: NiriConfig.options.cursor.theme
                    onSelected: newValue => SystemTheming.applyCursorTheme(newValue, NiriConfig.options.cursor.size)
                }

                ConfigSpinBox {
                    id: cursorSizeSpin
                    icon: "zoom_in"
                    text: Translation.tr("Cursor size")
                    value: NiriConfig.options.cursor.size
                    from: 16; to: 64; stepSize: 2
                    onValueChanged: {
                        if (value === NiriConfig.options.cursor.size) return
                        NiriConfig.options.cursor.size = value
                        cursorSizeApplyTimer.restart()
                    }
                    Timer {
                        id: cursorSizeApplyTimer
                        interval: 500
                        repeat: false
                        onTriggered: SystemTheming.applyCursorTheme(NiriConfig.options.cursor.theme, cursorSizeSpin.value)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "keyboard_hide"
                    text: Translation.tr("Hide while typing")
                    checked: NiriConfig.options.cursor.hideWhenTyping
                    onCheckedChanged: {
                        if (checked === NiriConfig.options.cursor.hideWhenTyping) return
                        NiriConfig.options.cursor.hideWhenTyping = checked
                    }
                }
            }
        }
    }
}
