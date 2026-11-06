import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Item {
    id: root

    readonly property int saturationSteps: 30
    readonly property int valueSteps: 30
    readonly property int hueSteps: 360

    // Store and apply together: picking a colour implies you want it kept, so
    // it also turns colour management on. The swatches, the hex field and the
    // Apply button all go through here instead of having three paths.
    function pickColour(hex: string): void {
        Config.options.light.keyboardColor.color = hex;
        Config.options.light.keyboardColor.enable = true;
        Brightness.kbMonitor.setColorHex(hex);
    }

    Component.onCompleted: {
        // Whatever is already on the hardware wins, then the stored choice.
        const applied = Brightness.kbMonitor?.color;
        const stored = Config.options.light.keyboardColor.color;
        currentColor = applied || (stored && stored !== "" ? stored : "#FFFFFF");
    }

    property string currentColor: "#FFFFFF"
    property real hue: 0
    property real saturation: 100
    property real value: 100

    // Update currentColor when HSV changes
    property var hsvColor: Qt.hsva(hue / 360, saturation / 100, value / 100, 1)

    onHueChanged: currentColor = hsvColor
    onSaturationChanged: currentColor = hsvColor
    onValueChanged: currentColor = hsvColor

    // When currentColor changes externally, update HSV
    onCurrentColorChanged: {
        const col = Qt.color(currentColor);
        hue = col.h * 360;
        saturation = col.s * 100;
        value = col.v * 100;
    }

    // A labelled slider for the three HSV controls. The caller keeps a
    // one-way binding on `value` and listens for `valueEdited`, so a reset
    // coming from outside still moves the thumb.
    component SliderCard: Rectangle {
        id: card

        property string title: ""
        property real value: 0
        property real from: 0
        property real to: 100
        property real step: 1
        signal valueEdited(real newValue)

        implicitWidth: 300
        implicitHeight: cardContent.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal

        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: card.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurface
                }

                Text {
                    text: Math.round(card.value).toString()
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colPrimary
                }
            }

            Slider {
                id: slider
                Layout.fillWidth: true
                from: card.from
                to: card.to
                stepSize: card.step
                // Follow the model again as soon as the user lets go, so an
                // outside reset is not swallowed by the drag binding.
                Binding {
                    target: slider
                    property: "value"
                    value: card.value
                    when: !slider.pressed
                }
                onMoved: card.valueEdited(value)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        Text {
            text: Translation.tr("Keyboard Color")
            font.pixelSize: Appearance.font.pixelSize.title
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
            Layout.maximumWidth: 400
            elide: Text.ElideRight
        }

        Text {
            text: Translation.tr("Set the keyboard backlight colour and brightness. Colours go through the system's keyboard backlight helper.")
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
            Layout.maximumWidth: 500
            wrapMode: Text.WordWrap
        }

        // Named colours, applied as soon as they are clicked. The same table
        // backs the quick-control select, so the two cannot drift apart.
        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 700
            spacing: 10
            visible: Brightness.kbMonitor.available

            MaterialSymbol {
                text: "palette"
                iconSize: Appearance.font.pixelSize.normal + 5
                color: Appearance.colors.colOnLayer1
            }

            CustomColorSelectionArray {
                spacing: 4
                swatchSize: 36
                options: Brightness.keyboardColors
                currentValue: Config.options.light.keyboardColor.color
                onSelected: newValue => root.pickColour(newValue)
            }
        }

        GridLayout {
            visible: Brightness.kbMonitor.available
            columns: 2
            columnSpacing: 16
            rowSpacing: 16
            Layout.maximumWidth: 700

            SliderCard {
                title: Translation.tr("Hue")
                value: hue
                from: 0
                to: 360
                step: 1
                onValueEdited: root.hue = newValue
                Layout.fillWidth: true
            }

            SliderCard {
                title: Translation.tr("Saturation")
                value: saturation
                from: 0
                to: 100
                step: 1
                onValueEdited: root.saturation = newValue
                Layout.fillWidth: true
            }

            SliderCard {
                title: Translation.tr("Brightness")
                // root.value, not `value`: unqualified it would bind to the
                // card's own property and never read the model.
                value: root.value
                from: 0
                to: 100
                step: 1
                onValueEdited: root.value = newValue
                Layout.fillWidth: true
            }

            Rectangle {
                id: colorPreview
                width: 120
                height: 120
                radius: 12
                color: currentColor
                border.width: 1
                border.color: Appearance.colors.colOutline
                Layout.rowSpan: 2
                Layout.columnSpan: 1

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "color_lens"
                    iconSize: 48
                    color: Appearance.colors.colOnSurface
                }
            }

            TextField {
                id: colorInput
                text: currentColor
                placeholderText: Translation.tr("#RRGGBB")
                Layout.fillWidth: true
                Layout.columnSpan: 1
                Layout.rowSpan: 1

                onEditingFinished: {
                    const c = Qt.color(text);
                    if (c.isValid) {
                        root.currentColor = c.name();
                        root.pickColour(c.name());
                    }
                }
            }

            Rectangle {
                Layout.rowSpan: 1
                Layout.columnSpan: 1
                Layout.minimumWidth: 120
                Layout.minimumHeight: 48
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    RippleButton {
                        text: Translation.tr("Apply")
                        colBackground: currentColor
                        colBackgroundHover: Qt.darker(currentColor, 1.1)
                        colRipple: Appearance.colors.colPrimaryHover
                        onClicked: root.pickColour(root.currentColor)
                        Layout.fillWidth: true
                    }

                    RippleButton {
                        text: Translation.tr("Reset")
                        colBackground: Appearance.colors.colSurfaceContainer
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHigh
                        colRipple: Appearance.colors.colPrimaryHover
                        onClicked: {
                            root.currentColor = "#FFFFFF";
                            root.hue = 0;
                            root.saturation = 0;
                            root.value = 100;
                            root.pickColour("#FFFFFF");
                        }
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // Say exactly what is missing rather than the old vague "may appear
        // disabled": on this machine the LED comes from the uniwill_wmi
        // module, which is listed in /etc/modules-load.d/ but is not loaded.
        NoticeBox {
            Layout.fillWidth: true
            visible: !Brightness.kbMonitor.available
            materialIcon: "memory"
            text: Translation.tr("No keyboard backlight device was found. It is provided by the uniwill_wmi module, which is listed in /etc/modules-load.d/ but is not loaded. Run: sudo modprobe uniwill_wmi - then reopen this page.")
        }

        // sudo -n cannot prompt from a background process, so whatever the
        // helper wrote to stderr is shown verbatim instead of being dropped.
        NoticeBox {
            Layout.fillWidth: true
            visible: !Brightness.kbMonitor.statusOk && Brightness.kbMonitor.statusMessage !== ""
            materialIcon: "error"
            text: Brightness.kbMonitor.statusMessage
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "palette"
            text: Translation.tr('Manage keyboard colour')
            checked: Config.options.light.keyboardColor.enable
            onCheckedChanged: {
                Config.options.light.keyboardColor.enable = checked;
                if (checked) Brightness.kbMonitor.applyFromConfig();
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "wallpaper"
            text: Translation.tr('Match the wallpaper colour')
            enabled: Config.options.light.keyboardColor.enable
            checked: Config.options.light.keyboardColor.followWallpaper
            onCheckedChanged: {
                Config.options.light.keyboardColor.followWallpaper = checked;
                if (checked) Brightness.kbMonitor.applyFromConfig();
            }
        }
    }
}

