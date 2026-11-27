import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    // The hosted Qt Test harness cannot call findChild on a QML object, so
    // the real items are exposed as named properties for assertions.
    readonly property var bluetoothSectionItem: bluetoothSection
    readonly property var pairedSectionItem: pairedSection
    readonly property var nearbySectionItem: nearbySection
    readonly property var enabledSwitchItem: enabledSwitch
    readonly property var emptyStateItem: emptyState

    // Thin wrappers keep the page testable and give every row the same write
    // path the right-pane dialog uses.
    function connectDevice(device) {
        if (device === null || device === undefined) return;
        BluetoothStatus.runAction("connect", device.address);
    }

    function disconnectDevice(device) {
        if (device === null || device === undefined) return;
        BluetoothStatus.runAction("disconnect", device.address);
    }

    function pairDevice(device) {
        if (device === null || device === undefined) return;
        BluetoothStatus.runAction("pair", device.address);
    }

    function forgetDevice(device) {
        if (device === null || device === undefined) return;
        BluetoothStatus.runAction("forget", device.address);
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 20

        ContentSection {
            id: bluetoothSection
            objectName: "bluetoothSection"
            icon: "bluetooth"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("Bluetooth")

            GroupedList {
                ConfigSwitch {
                    id: enabledSwitch
                    objectName: "bluetoothEnabledSwitch"
                    buttonIcon: "bluetooth"
                    text: Translation.tr("Bluetooth")
                    checked: BluetoothStatus.enabled
                    onCheckedChanged: BluetoothStatus.setPower(checked)
                }
                ConfigSwitch {
                    buttonIcon: "sync"
                    text: Translation.tr("Discover devices")
                    checked: BluetoothStatus.discovering
                    enabled: BluetoothStatus.enabled
                    onCheckedChanged: {
                        if (checked && !BluetoothStatus.discovering) BluetoothStatus.startDiscovery();
                        else if (!checked && BluetoothStatus.discovering) BluetoothStatus.stopDiscovery();
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !BluetoothStatus.available
                text: Translation.tr("Bluetooth is unavailable on this device.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        ContentSection {
            id: pairedSection
            objectName: "bluetoothPairedSection"
            icon: "link"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("Paired devices")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    id: emptyState
                    objectName: "bluetoothEmptyState"
                    Layout.fillWidth: true
                    visible: BluetoothStatus.friendlyDeviceList.length === 0
                    text: BluetoothStatus.enabled
                        ? Translation.tr("No paired devices. Discover devices to pair one.")
                        : Translation.tr("Bluetooth is off. Turn it on to see devices.")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                Repeater {
                    model: [
                        ...BluetoothStatus.connectedDevices,
                        ...BluetoothStatus.pairedButNotConnectedDevices
                    ]
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            iconSize: 20
                            text: modelData.icon !== "" ? modelData.icon : "bluetooth"
                            color: Appearance.colors.colOnSurface
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name !== "" ? modelData.name : modelData.address
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.normal
                                elide: Text.ElideRight
                            }
                            StyledText {
                                visible: modelData.batteryAvailable
                                text: modelData.battery + "%"
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        RippleButton {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                            enabled: BluetoothStatus.enabled
                            onClicked: modelData.connected
                                ? page.disconnectDevice(modelData)
                                : page.connectDevice(modelData)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: modelData.connected ? "link_off" : "link"
                                color: Appearance.colors.colPrimary
                            }
                        }
                        RippleButton {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                            enabled: BluetoothStatus.enabled
                            onClicked: page.forgetDevice(modelData)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "delete"
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            id: nearbySection
            objectName: "bluetoothNearbySection"
            icon: "bluetooth_searching"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("Nearby devices")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    visible: BluetoothStatus.unpairedDevices.length === 0
                    text: Translation.tr("No nearby devices found")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                Repeater {
                    model: BluetoothStatus.unpairedDevices
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            iconSize: 20
                            text: modelData.icon !== "" ? modelData.icon : "bluetooth"
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.name !== "" ? modelData.name : modelData.address
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.normal
                            elide: Text.ElideRight
                        }
                        RippleButton {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                            enabled: BluetoothStatus.enabled
                            onClicked: page.pairDevice(modelData)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "add"
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }
    }
}
