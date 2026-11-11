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

    MonitorConfigOption { id: monitorConfig }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        // Displays
        ContentSection {
            icon: "monitor"
            shape: MaterialShape.Shape.ClamShell
            title: Translation.tr("Displays")
            visible: monitorConfig.monitors.length > 0

            MonitorCanvas {
                id: monitorCanvas
                Layout.fillWidth: true
                monitorConfig: monitorConfig
            }

            ContentSubsection {
                Layout.topMargin: 10
                title: (monitorConfig.monitors[monitorCanvas.selectedIndex]?.name ?? "")
                    + " · "
                    + (monitorConfig.monitors[monitorCanvas.selectedIndex]?.description ?? "")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "tv_off"
                        text: Translation.tr("Enabled")
                        enabled: monitorConfig.monitors.length > 1
                        checked: !(monitorConfig.monitors[monitorCanvas.selectedIndex]?.disabled ?? false)
                        onCheckedChanged: {
                            if (checked === !(monitorConfig.monitors[monitorCanvas.selectedIndex]?.disabled ?? false)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { disabled: !checked })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }

                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "aspect_ratio"
                        text: Translation.tr("Resolution & Refresh Rate")
                        textRole: "display"
                        model: (monitorConfig.monitors[monitorCanvas.selectedIndex]?.availableModes ?? [])
                            .map(mode => ({ display: mode, value: mode }))
                        currentValue: monitorConfig.monitors[monitorCanvas.selectedIndex]?.currentMode ?? ""
                        onSelected: newValue => {
                            const mode = newValue
                            const parts = mode.match(/(\d+)x(\d+)@([\d.]+)Hz/)
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, {
                                currentMode: mode,
                                width: parseInt(parts[1]),
                                height: parseInt(parts[2]),
                                refreshRate: parseFloat(parts[3])
                            })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Orientation")
                        icon: "mobile_rotate"
                        currentValue: monitorConfig.monitors[monitorCanvas.selectedIndex]?.transform ?? 0
                        onSelected: newValue => {
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { transform: newValue })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                        options: [
                            { displayName: Translation.tr("Normal"), icon: "screen_rotation_alt", value: 0 },
                            { displayName: "90°",                    icon: "rotate_90_degrees_cw",  value: 1 },
                            { displayName: "180°",                   icon: "screen_rotation",       value: 2 },
                            { displayName: "270°",                   icon: "rotate_90_degrees_ccw", value: 3 },
                        ]
                    }

                    ConfigSpinBox {
                        icon: "zoom_in"
                        text: Translation.tr("Scale")
                        value: Math.round((monitorConfig.monitors[monitorCanvas.selectedIndex]?.scale ?? 1.0) * 100)
                        from: 50; to: 300; stepSize: 25
                        onValueChanged: {
                            const newVal = value / 100.0
                            if (newVal === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.scale ?? 1.0)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { scale: newVal })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }

                    ConfigSpinBox {
                        icon: "swap_horiz"
                        text: Translation.tr("Position X")
                        value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.x ?? 0
                        from: 0; to: 7680; stepSize: 1
                        onValueChanged: {
                            if (value === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.x ?? 0)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { x: value })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }

                    ConfigSpinBox {
                        icon: "swap_vert"
                        text: Translation.tr("Position Y")
                        value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.y ?? 0
                        from: 0; to: 4320; stepSize: 1
                        onValueChanged: {
                            if (value === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.y ?? 0)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { y: value })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
                    }
                }
            }

            ContentSubsection {
                Layout.topMargin: 10
                title: Translation.tr("HDR & Color Management")

                NoticeBox {
                    Layout.fillWidth: true
                    visible: monitorConfig.monitors[monitorCanvas.selectedIndex]?.hdrSupported === null
                    text: Translation.tr("Couldn't confirm this display's HDR capability from its EDID. Options are shown but may not do anything.")
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: monitorConfig.monitors[monitorCanvas.selectedIndex]?.hdrSupported === false
                    text: Translation.tr("This display's EDID does not report HDR support, so HDR options are disabled here. Open an issue in GitHub if you think this is a mistake.")
                }

                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Bit depth")
                        icon: "gradient"
                        currentValue: monitorConfig.monitors[monitorCanvas.selectedIndex]?.bitdepth
                            ?? (monitorConfig.monitors[monitorCanvas.selectedIndex]?.maxBpc ?? 8)
                        onSelected: newValue => {
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { bitdepth: newValue })
                            monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                        }
                        options: (() => {
                            const maxBpc = monitorConfig.monitors[monitorCanvas.selectedIndex]?.maxBpc ?? 8
                            return [
                                { displayName: "8-bit",  icon: "filter_8", value: 8  },
                                { displayName: "10-bit", icon: "palette",   value: 10 },
                                { displayName: "12-bit", icon: "hdr_on",   value: 12 },
                            ].filter(o => o.value <= maxBpc)
                        })()
                    }

                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "palette"
                        text: Translation.tr("Color management")
                        enabled: monitorConfig.monitors[monitorCanvas.selectedIndex]?.hdrSupported !== false
                        model: [
                            { displayName: Translation.tr("Auto"),       icon: "auto_awesome",  value: "auto"    },
                            { displayName: "sRGB",                       icon: "light_mode",    value: "srgb"    },
                            { displayName: Translation.tr("Wide (P3)"),  icon: "wb_iridescent", value: "wide"    },
                            { displayName: "HDR",                        icon: "hdr_on",        value: "hdr"     },
                            { displayName: Translation.tr("HDR (EDID)"), icon: "hdr_auto",      value: "hdredid" },
                        ]
                        currentValue: monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm ?? "auto"
                        onSelected: newValue => {
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { cm: newValue })
                            monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            enabled: monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdr" || monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdredid"
                            icon: "brightness_6"
                            text: Translation.tr("SDR brightness")
                            value: Math.round((monitorConfig.monitors[monitorCanvas.selectedIndex]?.sdrBrightness ?? 1.0) * 100)
                            from: 10; to: 300; stepSize: 5
                            onValueChanged: {
                                const newVal = value / 100.0
                                if (newVal === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.sdrBrightness ?? 1.0)) return
                                monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { sdrBrightness: newVal })
                                monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                            }
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            enabled: monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdr" || monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdredid"
                            icon: "contrast"
                            text: Translation.tr("SDR saturation")
                            value: Math.round((monitorConfig.monitors[monitorCanvas.selectedIndex]?.sdrSaturation ?? 1.0) * 100)
                            from: 10; to: 200; stepSize: 5
                            onValueChanged: {
                                const newVal = value / 100.0
                                if (newVal === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.sdrSaturation ?? 1.0)) return
                                monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { sdrSaturation: newVal })
                                monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "wb_twilight"
                            text: Translation.tr("SDR min (nits)")
                            value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.sdrMinLuminance ?? 0
                            from: 0; to: 100; stepSize: 1
                            enabled: monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdr" || monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdredid"
                            onValueChanged: {
                                if (value === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.sdrMinLuminance ?? 0)) return
                                monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { sdrMinLuminance: value })
                                monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                            }
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "wb_sunny"
                            text: Translation.tr("SDR max (nits)")
                            value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.sdrMaxLuminance ?? 250
                            from: 50; to: 2000; stepSize: 10
                            enabled: monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdr" || monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdredid"
                            onValueChanged: {
                                if (value === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.sdrMaxLuminance ?? 250)) return
                                monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { sdrMaxLuminance: value })
                                monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "nightlight"
                            text: Translation.tr("HDR min (nits)")
                            value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.minLuminance ?? 0
                            from: 0; to: 100; stepSize: 1
                            enabled: monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdr" || monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdredid"
                            onValueChanged: {
                                if (value === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.minLuminance ?? 0)) return
                                monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { minLuminance: value })
                                monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                            }
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "hdr_strong"
                            text: Translation.tr("HDR peak (nits)")
                            value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.maxLuminance ?? 1000
                            from: 100; to: 10000; stepSize: 50
                            enabled: monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdr" || monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdredid"
                            onValueChanged: {
                                if (value === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.maxLuminance ?? 1000)) return
                                monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { maxLuminance: value })
                                monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                            }
                        }
                    }

                    ConfigSpinBox {
                        icon: "hdr_weak"
                        text: Translation.tr("HDR max average luminance (nits)")
                        value: monitorConfig.monitors[monitorCanvas.selectedIndex]?.maxAvgLuminance ?? 250
                        from: 50; to: 5000; stepSize: 10
                        enabled: monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdr" || monitorConfig.monitors[monitorCanvas.selectedIndex]?.cm === "hdredid"
                        onValueChanged: {
                            if (value === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.maxAvgLuminance ?? 250)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { maxAvgLuminance: value })
                            monitorConfig.saveHdr(monitorCanvas.selectedIndex)
                        }
                    }
                }
            }
        }
    }
}
