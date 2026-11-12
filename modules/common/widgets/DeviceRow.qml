pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Two-line device row (per user spec):
 *
 *   name device .................. mute toggler
 *   [========= volume slider =========]
 *
 * The slider is full width so volume is easy to grab; the name row keeps
 * the optional icon and default-star (shown in the waffle list, hidden in
 * the Devices panel, which shows only the three essentials). Fixed-width
 * slots (icon 18 / star 18 / mute 22) keep the right edge aligned across
 * rows.
 *
 * State is re-asserted in `onDevChanged` because user interaction (drag)
 * severs plain declarative bindings in Qt; AudioDevices replaces the `dev`
 * object on every meaningful pactl change, which re-drives the slider —
 * skipped while a drag owns it.
 */
ColumnLayout {
    id: root

    required property string deviceName
    property bool isOutput: true
    property bool showIcon: true
    property bool showStar: true

    readonly property var dev: root.isOutput
        ? AudioDevices.sink(root.deviceName)
        : AudioDevices.source(root.deviceName)
    readonly property bool isDefault: AudioDevices.isDefault(root.deviceName)
    readonly property bool muted: root.dev?.mute ?? false

    spacing: 2

    onDevChanged: {
        // Every fresh parse re-drives the slider (see header comment).
        if (root.dev && !volSlider.pressed) volSlider.value = root.dev.volume;
    }

    function set(value) {
        if (root.isOutput) AudioDevices.setSinkVolume(root.deviceName, value);
        else AudioDevices.setSourceVolume(root.deviceName, value);
    }

    function toggleMute() {
        if (root.isOutput) AudioDevices.setSinkMute(root.deviceName, !root.muted);
        else AudioDevices.setSourceMute(root.deviceName, !root.muted);
    }

    function makeDefault() {
        if (root.isOutput) AudioDevices.setDefaultSink(root.deviceName);
        else AudioDevices.setDefaultSource(root.deviceName);
    }

    // ------------------------------------------------------- name row

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Item {
            visible: root.showIcon
            Layout.preferredWidth: 18
            Layout.preferredHeight: 16

            MaterialSymbol {
                anchors.centerIn: parent
                text: AudioDevices.icon(root.deviceName, root.isOutput)
                iconSize: 16
                color: root.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.dev?.description || root.deviceName
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.bold: root.isDefault
            color: root.isDefault ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
        }

        Item {
            visible: root.showStar
            Layout.preferredWidth: 18
            Layout.preferredHeight: 16

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.isDefault ? "star" : "star_border"
                iconSize: Appearance.font.pixelSize.smaller + 2
                color: root.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colSubtext

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.makeDefault()
                }
            }
        }

        Item {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 18

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.muted ? "volume_off" : (root.dev?.volume ?? 100) > 0 ? "volume_up" : "volume_mute"
                iconSize: Appearance.font.pixelSize.small + 4
                color: root.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnSecondaryContainer

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleMute()
                }
            }
        }
    }

    // ------------------------------------------------------- volume row

    StyledSlider {
        id: volSlider
        Layout.fillWidth: true
        from: 0
        to: 150
        configuration: StyledSlider.Configuration.S
        // The slider runs 0–150 (pactl scale, allows >100% boost): show the
        // true volume percent in the tooltip, not the share of the range.
        usePercentTooltip: false
        tooltipContent: `${Math.round(value)}%`
        value: root.dev ? root.dev.volume : 100
        onMoved: volTimer.restart()
    }

    Timer {
        id: volTimer
        interval: 60
        onTriggered: root.set(volSlider.value)
    }
}
