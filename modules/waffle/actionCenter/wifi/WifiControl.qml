import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
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
    // field, in the service's own order (the connected network first).
    readonly property var visibleNetworks: StringUtils.filterByQuery(Network.friendlyWifiNetworks, searchField.text, ["ssid"])

    Component.onCompleted: {
        Network.rescanWifi();
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
                            title: Translation.tr("Wi-Fi")
                        }
                        WSwitch {
                            id: toggleSwitch
                            Layout.rightMargin: 12
                            checked: Network.wifiStatus !== "disabled"
                            onCheckedChanged: {
                                Network.enableWifi(checked);
                                Network.rescanWifi();
                            }
                        }
                    }
                    FadeLoader {
                        Layout.leftMargin: -4
                        Layout.rightMargin: -4
                        Layout.fillWidth: true
                        shown: Network.wifiScanning
                        visible: true
                        sourceComponent: WIndeterminateProgressBar {}
                    }
                }

                WSearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search networks")
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
                    delegate: WWifiNetworkItem {
                        required property WifiAccessPoint modelData
                        wifiNetwork: modelData
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
                    text: Translation.tr("No networks match your search")
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
                text: Translation.tr("More Internet settings")
                onClicked: {
                    Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "waffleSidebarLeft", "toggle"]);
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.network]);
                }
            }
            WBorderlessButton {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 12
                enabled: !Network.wifiScanning

                onClicked: {
                    Network.rescanWifi();
                }

                contentItem: FluentIcon {
                    icon: "arrow-counterclockwise"
                }
            }
        }
    }
}
