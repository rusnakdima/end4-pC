pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

WindowDialog {
    id: root
    property bool isSink: true
    // "Details" now flips this dialog to the built-in pavucontrol-style
    // device panel instead of launching an external app.
    property bool showingDevices: false
    backgroundHeight: 600

    WindowDialogTitle {
        text: root.showingDevices ? Translation.tr("Audio devices")
            : root.isSink ? Translation.tr("Audio output") : Translation.tr("Audio input")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    VolumeDialogContent {
        isSink: root.isSink
        visible: !root.showingDevices
    }

    AudioDevicesPanel {
        visible: root.showingDevices
        Layout.fillWidth: true
    }

    WindowDialogButtonRow {
        DialogButton {
            buttonText: root.showingDevices ? Translation.tr("Back") : Translation.tr("Details")
            onClicked: root.showingDevices = !root.showingDevices
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
