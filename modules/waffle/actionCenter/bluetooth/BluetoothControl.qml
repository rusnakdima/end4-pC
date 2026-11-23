import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Bluetooth
import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

Item {
    id: root

    // The list the user sees: the service list narrowed by the search
    // field, in the service's own order (connected devices first).
    readonly property var visibleNetworks: StringUtils.filterByQuery(BluetoothStatus.friendlyDeviceList, searchField.text, ["name"])

    WPanelPageColumn {
        anchors.fill: parent

        BodyRectangle {
            implicitHeight: 400
            implicitWidth: 50

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                ColumnLayout {
                    implicitHeight: headerRow.implicitHeight
                    Layout.fillWidth: true
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        HeaderRow {
                            id: headerRow
                            Layout.fillWidth: true
                            title: Translation.tr("Bluetooth")
                        }
                        WSwitch {
                            id: toggleSwitch
                            Layout.rightMargin: 12
                            checked: BluetoothStatus.enabled
                            onCheckedChanged: BluetoothStatus.setPowerAndDiscover(checked)
                        }
                    }
                    FadeLoader {
                        Layout.leftMargin: -4
                        Layout.rightMargin: -4
                        Layout.fillWidth: true
                        shown: BluetoothStatus.discovering
                        visible: true
                        sourceComponent: WIndeterminateProgressBar {}
                    }
                }

                WSearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search devices")
                }

                // The list viewport: the body has a fixed height, so this
                // zone keeps the search field in place and gives an empty
                // result the same space as a full list.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: listView
                        anchors.fill: parent

                        clip: true
                        spacing: 4

                        TouchpadScrollArea { flickable: listView }

                        model: ScriptModel {
                            values: root.visibleNetworks
                        }
                        delegate: BluetoothDeviceItem {
                            required property var modelData
                            device: modelData
                            width: ListView.view.width
                        }
                    }
                    WText {
                        // Only a query has an explanation to show; without
                        // one an empty list leaves the zone blank.
                        visible: searchField.text.length > 0 && root.visibleNetworks.length === 0
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        color: Looks.colors.subfg
                        text: Translation.tr("No devices match your search")
                    }
                }
            }
        }

        WPanelSeparator {}

        FooterRectangle {
            WTextButton {
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                }
                text: Translation.tr("More Bluetooth settings")
                onClicked: {
                    Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "waffleSidebarLeft", "toggle"]);
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.bluetooth]);
                }
            }
            WBorderlessButton {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 12
                enabled: !BluetoothStatus.discovering && BluetoothStatus.enabled

                onClicked: {
                    BluetoothStatus.startDiscovery();
                }

                contentItem: FluentIcon {
                    icon: "arrow-counterclockwise"
                }
            }
        }
    }
}
