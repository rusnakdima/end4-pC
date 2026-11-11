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

    // "ok" | "misplaced" | "missing"
    property string includeStatus: "ok"

    Component.onCompleted: includeCheckProc.running = true

    Process {
        id: includeCheckProc
        // ok = all include lines present and nothing but blanks/comments/includes after them
        command: ["sh", "-c", `cfg="$HOME/.config/niri/config.kdl"
missing=0
for f in shell outputs autostart binds; do
    grep -qs "qssettings/$f.kdl" "$cfg" || missing=1
done
if [ "$missing" = 1 ]; then echo missing
elif awk '/qssettings\\/shell.kdl/ {found=1; next} found && NF && $0 !~ /qssettings/ && $0 !~ /^[ \\t]*\\/\\// {bad=1} END {exit bad}' "$cfg"; then echo ok
else echo misplaced
fi`]
        stdout: StdioCollector {
            onStreamFinished: page.includeStatus = text.trim()
        }
    }

    Process {
        id: setupIncludesProc
        // Backs up config.kdl, strips qssettings include lines wherever they are,
        // re-appends them at the end. Writes through symlinks (stow-managed dotfiles).
        command: ["sh", "-c", `cfg="$HOME/.config/niri/config.kdl"
cp -L "$cfg" "$cfg.backup.$(date +%s)" || exit 1
tmp=$(mktemp)
grep -vE 'qssettings/(shell|outputs|autostart|binds)\\.kdl' "$cfg" > "$tmp"
printf '\\ninclude optional=true "qssettings/shell.kdl"\\ninclude optional=true "qssettings/outputs.kdl"\\ninclude optional=true "qssettings/autostart.kdl"\\ninclude optional=true "qssettings/binds.kdl"\\n' >> "$tmp"
cat "$tmp" > "$cfg"
rm -f "$tmp"`]
        onExited: includeCheckProc.running = true
    }

    MonitorConfigOption { id: monitorConfig }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        NoticeBox {
            visible: page.includeStatus !== "ok"
            Layout.fillWidth: true
            text: page.includeStatus === "misplaced"
                ? Translation.tr("The qssettings include lines are in your config.kdl but not at the end. Later config wins in niri, so your own settings currently override these. Fix moves them to the bottom (a backup of config.kdl is made first).")
                : Translation.tr("These settings are saved to ~/.config/niri/qssettings/. Setup adds the include lines at the end of your config.kdl (a backup is made first):") + "\n\n" + NiriConfig.includeLines

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                Layout.fillWidth: false
                buttonRadius: Appearance.rounding.small
                materialIcon: page.includeStatus === "misplaced" ? "build" : "auto_fix_high"
                mainText: page.includeStatus === "misplaced" ? Translation.tr("Fix") : Translation.tr("Setup")
                onClicked: setupIncludesProc.running = true
                colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
            }

            RippleButtonWithIcon {
                id: copyIncludesButton
                property bool justCopied: false
                Layout.fillWidth: false
                buttonRadius: Appearance.rounding.small
                materialIcon: justCopied ? "check" : "content_copy"
                mainText: justCopied ? Translation.tr("Copied!") : Translation.tr("Copy lines")
                onClicked: {
                    copyIncludesButton.justCopied = true
                    Quickshell.clipboardText = NiriConfig.includeLines
                    revertCopyTimer.restart()
                }
                colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                Timer {
                    id: revertCopyTimer
                    interval: 1500
                    onTriggered: copyIncludesButton.justCopied = false
                }
            }
        }

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

                    ConfigSwitch {
                        buttonIcon: "autoplay"
                        text: Translation.tr("Variable refresh rate (VRR)")
                        checked: monitorConfig.monitors[monitorCanvas.selectedIndex]?.vrr ?? false
                        onCheckedChanged: {
                            if (checked === (monitorConfig.monitors[monitorCanvas.selectedIndex]?.vrr ?? false)) return
                            monitorConfig.updateMonitor(monitorCanvas.selectedIndex, { vrr: checked })
                            monitorConfig.applyAndSave(monitorCanvas.selectedIndex)
                        }
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
        }
    }
}
