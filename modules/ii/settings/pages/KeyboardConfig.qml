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

    Component.onCompleted: {
        if (Brightness.kbMonitor?.color !== null) {
            currentColor = Brightness.kbMonitor.color;
        }
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
            text: Translation.tr("Set the RGB color of your laptop keyboard backlight. Available on supported hardware via asusctl.")
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
            Layout.maximumWidth: 500
            wrapMode: Text.WordWrap
        }

        GridLayout {
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
                        Brightness.kbMonitor.setColorHex(text);
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
                        onClicked: Brightness.kbMonitor.setColorHex(currentColor)
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
                            Brightness.kbMonitor.setColorHex("#FFFFFF");
                        }
                        Layout.fillWidth: true
                    }
                }
            }
        }

        Text {
            text: Translation.tr("If your keyboard does not support color control, this page will appear disabled.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
            Layout.maximumWidth: 600
            wrapMode: Text.WordWrap
            visible: !Brightness.kbMonitor.hasColor
        }
    }
}

