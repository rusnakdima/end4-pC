pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Shared device panel — exactly two parts: Output devices and Input
 * devices. Rows are the essentials only (name + volume slider + mute;
 * icon and star hidden here, port pickers not shown), restricted to
 * devices that actually expose volume control (see
 * AudioDevices.volumeCapable). Fixed-width slots in DeviceRow keep every
 * row's columns aligned. Width-safe from the 300 px overlay widget to
 * the ~360 px dialog: names elide, the slider keeps its 110 px.
 */
ColumnLayout {
    id: root
    spacing: 4

    component SectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.bold: true
        color: Appearance.colors.colSubtext
        Layout.topMargin: 8
        Layout.bottomMargin: 2
    }

    SectionLabel {
        text: Translation.tr("Output devices")
        visible: AudioDevices.outputNames.length > 0
    }

    Repeater {
        model: AudioDevices.outputNames
        delegate: DeviceRow {
            required property string modelData
            deviceName: modelData
            isOutput: true
            showIcon: false
            showStar: false
            Layout.fillWidth: true
        }
    }

    SectionLabel {
        text: Translation.tr("Input devices")
        visible: AudioDevices.inputNames.length > 0
    }

    Repeater {
        model: AudioDevices.inputNames
        delegate: DeviceRow {
            required property string modelData
            deviceName: modelData
            isOutput: false
            showIcon: false
            showStar: false
            Layout.fillWidth: true
        }
    }
}
