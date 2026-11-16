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

    Component.onCompleted: {
        if (Bluetooth.defaultAdapter.enabled) Bluetooth.defaultAdapter.discovering = true;
    }
    Component.onDestruction: {
        Bluetooth.defaultAdapter.discovering = false;
    }

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
                            checked: Bluetooth.defaultAdapter?.enabled ?? false
                            onCheckedChanged: {
                                if (Bluetooth.defaultAdapter) {
                                    Bluetooth.defaultAdapter.enabled = checked;
                                    if (checked) {
                                        Bluetooth.defaultAdapter.discovering = true;
                                    } else {
                                        Bluetooth.defaultAdapter.discovering = false;
                                    }
                                }
                            }
                        }
                    }
                    FadeLoader {
                        Layout.leftMargin: -4
                        Layout.rightMargin: -4
                        Layout.fillWidth: true
                        shown: Bluetooth.defaultAdapter?.discovering ?? false
                        visible: true
                        sourceComponent: WIndeterminateProgressBar {}
                    }
                }

                WSearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search devices")
                }

                StyledListView {
                    id: listView
                    visible: root.visibleNetworks.length > 0
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    animateAppearance: false

                    contentHeight: contentLayout.implicitHeight
                    contentWidth: width
                    clip: true
                    spacing: 4

                    model: ScriptModel {
                        values: root.visibleNetworks
                    }
                    delegate: BluetoothDeviceItem {
                        required property BluetoothDevice modelData
                        device: modelData
                        width: ListView.view.width
                    }
                }
                WText {
                    // Only a query can be empty of matches: with no query
                    // an empty list keeps the look it has today.
                    visible: searchField.text.length > 0 && root.visibleNetworks.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    horizontalAlignment: Text.AlignHCenter
                    color: Looks.colors.subfg
                    text: Translation.tr("No devices match your search")
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
                enabled: !Bluetooth.defaultAdapter?.discovering && Bluetooth.defaultAdapter?.enabled

                onClicked: {
                    Bluetooth.defaultAdapter.discovering = true;
                }

                contentItem: FluentIcon {
                    icon: "arrow-counterclockwise"
                }
            }
        }
    }
}
