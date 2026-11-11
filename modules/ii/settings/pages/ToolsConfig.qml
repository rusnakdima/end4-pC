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
            icon: "select_window"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Overlay")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "high_density"
                    text: Translation.tr("Enable opening zoom animation")
                    checked: Config.options.overlay.openingZoomAnimation
                    onCheckedChanged: {
                        Config.options.overlay.openingZoomAnimation = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "texture"
                    text: Translation.tr("Darken screen")
                    checked: Config.options.overlay.darkenScreen
                    onCheckedChanged: {
                        Config.options.overlay.darkenScreen = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Floating Image")
                GroupedList {
                    ConfigTextArea {
                        id: floatingImageSourceField
                        Layout.fillWidth: true
                        fieldWidth: 430
                        buttonIcon: "imagesmode"
                        text: Translation.tr("Image source")
                        value: Config.options.overlay.floatingImage.imageSource
                        onValueChanged: {
                            floatingImageSourceDebounceTimer.restart();
                        }

                        Timer {
                            id: floatingImageSourceDebounceTimer
                            interval: 1000
                            repeat: false
                            onTriggered: {
                                Config.options.overlay.floatingImage.imageSource = floatingImageSourceField.value;
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Crosshair")

                Rectangle {
                    id: crosshairCard
                    Layout.fillWidth: true
                    implicitHeight: crosshairCol.implicitHeight + 28
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: crosshairCol
                        anchors { fill: parent; margins: 14 }
                        spacing: 8

                        ConfigTextArea {
                            id: crosshairCodeField
                            Layout.fillWidth: true
                            buttonIcon: "point_scan"
                            text: Translation.tr("Crosshair code")
                            placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
                            value: Config.options.crosshair.code
                            onValueChanged: {
                                crosshairCodeDebounceTimer.restart();
                            }

                            Timer {
                                id: crosshairCodeDebounceTimer
                                interval: 1000
                                repeat: false
                                onTriggered: {
                                    Config.options.crosshair.code = crosshairCodeField.value;
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.leftMargin: 8
                                Layout.fillWidth: true
                                text: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.Wrap
                            }
                            RippleButtonWithIcon {
                                id: editorButton
                                Layout.fillWidth: true
                                Layout.rightMargin: 6
                                Layout.preferredHeight: 40
                                buttonRadius: Appearance.rounding.normal
                                materialIcon: "open_in_new"
                                mainText: Translation.tr("Open editor")
                                onClicked: {
                                    Qt.openUrlExternally(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "screenshot_frame_2"
            shape: MaterialShape.Shape.PuffyDiamond
            title: Translation.tr("Region selector (screen snipping/Google Lens)")

            ContentSubsection {
                title: Translation.tr("Hint target regions")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "select_window"
                        text: Translation.tr('Windows')
                        checked: Config.options.regionSelector.targetRegions.windows
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.windows = checked;
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "right_panel_open"
                        text: Translation.tr('Layers')
                        checked: Config.options.regionSelector.targetRegions.layers
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.layers = checked;
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "nearby"
                        text: Translation.tr('Content')
                        checked: Config.options.regionSelector.targetRegions.content
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.content = checked;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Google Lens")

                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Selection Type")
                        icon: "ink_selection"
                        currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                        onSelected: newValue => {
                            Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                        }
                        options: [
                            { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                            { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                        ]
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Rectangular selection")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "point_scan"
                        text: Translation.tr("Show aim lines")
                        checked: Config.options.regionSelector.rect.showAimLines
                        onCheckedChanged: {
                            Config.options.regionSelector.rect.showAimLines = checked;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Circle selection")

                GroupedList {
                    ConfigSpinBox {
                        icon: "eraser_size_3"
                        text: Translation.tr("Stroke width")
                        value: Config.options.regionSelector.circle.strokeWidth
                        from: 1
                        to: 20
                        stepSize: 1
                        onValueChanged: {
                            Config.options.regionSelector.circle.strokeWidth = value;
                        }
                    }

                    ConfigSpinBox {
                        icon: "screenshot_frame_2"
                        text: Translation.tr("Padding")
                        value: Config.options.regionSelector.circle.padding
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: {
                            Config.options.regionSelector.circle.padding = value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "voting_chip"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("On-screen display")
            GroupedList {
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Timeout (ms)")
                    value: Config.options.osd.timeout
                    from: 100
                    to: 3000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.osd.timeout = value;
                    }
                }
            }
        }
    }
}
