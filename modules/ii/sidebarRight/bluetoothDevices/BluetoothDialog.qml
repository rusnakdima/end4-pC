import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell
import Quickshell.Wayland

WindowDialog {
    id: root
    // The list the user sees: the service list narrowed by the search
    // field, in the service's own order (connected devices first).
    readonly property var visibleNetworks: StringUtils.filterByQuery(BluetoothStatus.friendlyDeviceList, searchField.text, ["name"])
    backgroundHeight: 600

    WindowDialogTitle {
        text: Translation.tr("Bluetooth devices")
    }

    DialogSearchField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search devices")
    }

    WindowDialogSeparator {
        visible: !(Bluetooth.defaultAdapter?.discovering ?? false)
    }
    StyledIndeterminateProgressBar {
        visible: Bluetooth.defaultAdapter?.discovering ?? false
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    ListView {
        id: devicesView
        visible: root.visibleNetworks.length > 0
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        clip: true
        spacing: 0

        model: ScriptModel {
            values: root.visibleNetworks
        }

        TouchpadScrollArea { flickable: devicesView }

        delegate: BluetoothDeviceItem {
            required property BluetoothDevice modelData
            device: modelData
            width: ListView.view.width
        }
    }
    StyledText {
        // Only a query can be empty of matches: with no query an empty
        // list keeps the look it has today.
        visible: searchField.text.length > 0 && root.visibleNetworks.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalAlignment: Text.AlignHCenter
        color: Appearance.colors.colSubtext
        text: Translation.tr("No devices match your search")
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
                GlobalStates.sidebarRightOpen = false;
            }
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
