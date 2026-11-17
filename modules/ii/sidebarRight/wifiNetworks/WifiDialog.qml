import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    // The list the user sees: the service list narrowed by the search
    // field, in the service's own order (the connected network first).
    readonly property var visibleNetworks: StringUtils.filterByQuery(Network.friendlyWifiNetworks, searchField.text, ["ssid"])
    backgroundHeight: 600

    WindowDialogTitle {
        text: Translation.tr("Connect to Wi-Fi")
    }

    DialogSearchField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search networks")
    }

    WindowDialogSeparator {
        visible: !Network.wifiScanning
    }
    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    // The list viewport. The dialog keeps a fixed height, so this zone always
    // reserves the same space between the search bar and the footer: an empty
    // result draws its message inside the zone instead of collapsing the
    // content and leaving the search block alone in the panel.
    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        ListView {
            id: networksView
            anchors.fill: parent

            clip: true
            spacing: 0

            model: ScriptModel {
                values: root.visibleNetworks
            }

            TouchpadScrollArea { flickable: networksView }

            delegate: WifiNetworkItem {
                required property WifiAccessPoint modelData
                wifiNetwork: modelData
                width: ListView.view.width
            }
        }

        StyledText {
            // Without a query an empty list leaves the zone blank, as before;
            // a query always gets an explanation in the same zone.
            visible: searchField.text.length > 0 && root.visibleNetworks.length === 0
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colSubtext
            text: Translation.tr("No networks match your search")
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
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