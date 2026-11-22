import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models.hyprland
import qs.services

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    MonitorConfigOption { id: monitorConfig }

    readonly property var internalMonitors: monitorConfig.monitors.filter(m => ProjectionUtils.isInternal(m))
    readonly property var externalMonitors: monitorConfig.monitors.filter(m => !ProjectionUtils.isInternal(m))

    readonly property var modeOptions: ProjectionUtils.modes.map(m => ({
        displayName: Translation.tr(m.label), icon: m.icon, value: m.value
    }))
    readonly property var placementOptions: ProjectionUtils.placements.map(p => ({
        displayName: Translation.tr(p.label), icon: p.icon, value: p.value
    }))

    function monitorIndex(name) {
        return monitorConfig.monitors.findIndex(m => m.name === name)
    }

    function setMode(mode) {
        monitorConfig.setProjection(mode, monitorConfig.projectionPlacement || "right")
    }

    component ProjectionCard: Item {
        id: card
        property string value
        property string label
        property string icon
        property string description
        property bool selected: monitorConfig.projectionMode === card.value

        Layout.fillWidth: true
        Layout.preferredHeight: 132

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: card.selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
            border.width: card.selected ? 2 : 1
            border.color: card.selected ? Appearance.colors.colSecondary : Appearance.colors.colLayer0Border
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            MaterialSymbol {
                text: card.icon
                iconSize: Appearance.font.pixelSize.xxlarge
                color: card.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                text: card.label
                font.weight: Font.DemiBold
                font.pixelSize: Appearance.font.pixelSize.normal
                color: card.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                text: card.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.setMode(card.value)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 20

        NoticeBox {
            Layout.fillWidth: true
            visible: externalMonitors.length === 0
            materialIcon: "desktop_access_disabled"
            text: Translation.tr("Connect an external monitor by cable to use projection modes.")
        }

        ContentSection {
            icon: "desktop_windows"
            shape: MaterialShape.Shape.ClamShell
            title: Translation.tr("Projection mode")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ProjectionCard {
                        value: "pc"
                        label: Translation.tr("PC screen only")
                        icon: "laptop_mac"
                        description: Translation.tr("Use only the built-in screen.")
                    }
                    ProjectionCard {
                        value: "duplicate"
                        label: Translation.tr("Duplicate")
                        icon: "content_copy"
                        description: Translation.tr("Show the same image on every screen.")
                    }
                    ProjectionCard {
                        value: "extend"
                        label: Translation.tr("Extend")
                        icon: "desktop_windows"
                        description: Translation.tr("Span the desktop across all screens.")
                    }
                    ProjectionCard {
                        value: "second"
                        label: Translation.tr("Second screen only")
                        icon: "tv"
                        description: Translation.tr("Use only the external screen.")
                    }
                }

                ConfigSelectionArray {
                    visible: ["extend", "second"].includes(monitorConfig.projectionMode)
                    text: Translation.tr("External screen placement")
                    icon: "open_with"
                    options: page.placementOptions
                    currentValue: monitorConfig.projectionPlacement
                    onSelected: value => monitorConfig.setProjection(monitorConfig.projectionMode, value)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("The chosen mode is restored when a monitor is plugged in or after a compositor reload. Duplicate uses Hyprland's native mirror rule, so both screens show the same image.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }

        ContentSection {
            icon: "monitor"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Arrangement")

            MonitorCanvas {
                Layout.fillWidth: true
                monitorConfig: monitorConfig
            }
        }

        ContentSection {
            icon: "aspect_ratio"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("External monitor format")
            visible: externalMonitors.length > 0

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: page.externalMonitors

                    ContentSubsection {
                        required property var modelData
                        Layout.fillWidth: true
                        title: `${modelData.name} · ${modelData.description ?? ""}`

                        GroupedList {
                            ConfigComboBox {
                                Layout.fillWidth: true
                                buttonIcon: "aspect_ratio"
                                text: Translation.tr("Resolution & Refresh Rate")
                                model: (modelData.availableModes ?? []).map(mode => ({ displayName: mode, value: mode }))
                                currentValue: modelData.currentMode ?? ""
                                onSelected: value => {
                                    const idx = page.monitorIndex(modelData.name)
                                    if (idx < 0) return
                                    const parts = String(value).match(/(\d+)x(\d+)@([\d.]+)Hz/)
                                    const changes = { currentMode: value }
                                    if (parts) {
                                        changes.width = parseInt(parts[1])
                                        changes.height = parseInt(parts[2])
                                        changes.refreshRate = parseFloat(parts[3])
                                    }
                                    monitorConfig.updateMonitor(idx, changes)
                                    monitorConfig.applyAndSave(idx)
                                }
                            }

                            ConfigSpinBox {
                                icon: "zoom_in"
                                text: Translation.tr("Scale")
                                value: Math.round((modelData.scale ?? 1.0) * 100)
                                from: 50; to: 300; stepSize: 25
                                onValueChanged: {
                                    const idx = page.monitorIndex(modelData.name)
                                    if (idx < 0) return
                                    const next = value / 100.0
                                    if (next === (modelData.scale ?? 1.0)) return
                                    monitorConfig.updateMonitor(idx, { scale: next })
                                    monitorConfig.applyAndSave(idx)
                                }
                            }

                            ConfigSelectionArray {
                                text: Translation.tr("Orientation")
                                icon: "mobile_rotate"
                                currentValue: modelData.transform ?? 0
                                onSelected: value => {
                                    const idx = page.monitorIndex(modelData.name)
                                    if (idx < 0) return
                                    monitorConfig.updateMonitor(idx, { transform: value })
                                    monitorConfig.applyAndSave(idx)
                                }
                                options: [
                                    { displayName: Translation.tr("Normal"), icon: "screen_rotation_alt", value: 0 },
                                    { displayName: "90°", icon: "rotate_90_degrees_cw", value: 1 },
                                    { displayName: "180°", icon: "screen_rotation", value: 2 },
                                    { displayName: "270°", icon: "rotate_90_degrees_ccw", value: 3 }
                                ]
                            }
                        }
                    }
                }
            }
        }
    }
}
