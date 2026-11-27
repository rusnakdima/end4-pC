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

    // Exposed for the hosted Qt Test harness, which cannot call findChild on
    // a QML object. The named items below are the real page items.
    readonly property var connectionSectionItem: connectionSection
    readonly property var availableSectionItem: availableSection
    readonly property var savedSectionItem: savedSection
    readonly property var enabledSwitchItem: enabledSwitch
    readonly property var emptyStateItem: emptyState

    // Thin wrappers keep the page testable without touching NetworkManager and
    // give every row the same write path the right-pane dialog uses.
    function connectNetwork(ap) {
        if (ap === null || ap === undefined) return;
        Network.connectToWifiNetwork(ap);
    }

    function disconnectNetwork(ssid) {
        if (String(ssid ?? "") === "") return;
        Network.disconnectWifiNetwork(ssid);
    }

    function forgetNetwork(ssid) {
        if (String(ssid ?? "") === "") return;
        Network.forgetWifiNetwork(ssid);
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 20

        ContentSection {
            id: connectionSection
            objectName: "wifiConnectionSection"
            icon: "wifi"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("Connection")

            GroupedList {
                ConfigSwitch {
                    id: enabledSwitch
                    objectName: "wifiEnabledSwitch"
                    buttonIcon: "wifi"
                    text: Translation.tr("Wi-Fi")
                    checked: Network.wifiEnabled
                    onCheckedChanged: Network.enableWifi(checked)
                }
                ConfigSwitch {
                    buttonIcon: "sync"
                    text: Translation.tr("Scanning")
                    checked: Network.wifiScanning
                    enabled: Network.wifiEnabled
                    onCheckedChanged: {
                        if (checked && !Network.wifiScanning) Network.rescanWifi();
                    }
                }
            }
        }

        ContentSection {
            id: availableSection
            objectName: "wifiAvailableSection"
            icon: "wifi_find"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("Available networks")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    id: emptyState
                    objectName: "wifiEmptyState"
                    Layout.fillWidth: true
                    visible: Network.friendlyWifiNetworks.length === 0
                    text: Network.wifiEnabled
                        ? Translation.tr("No networks found. Try scanning again.")
                        : Translation.tr("Wi-Fi is off. Turn it on to see networks.")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                Repeater {
                    model: Network.friendlyWifiNetworks
                    delegate: RippleButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        buttonRadius: Appearance.rounding.small
                        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                        enabled: !Network.wifiConnecting
                        onClicked: page.connectNetwork(modelData)
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol {
                                Layout.preferredWidth: 22
                                iconSize: 20
                                text: modelData.active ? "wifi" : "wifi_2_bar"
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.ssid ?? Translation.tr("Hidden network")
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.normal
                                elide: Text.ElideRight
                            }
                            MaterialSymbol {
                                iconSize: 18
                                visible: !!modelData.protected || !!modelData.secured
                                text: "lock"
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            MaterialSymbol {
                                iconSize: 18
                                visible: !!modelData.active
                                text: "check"
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            id: savedSection
            objectName: "wifiSavedSection"
            icon: "bookmark_border"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("Saved networks")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    visible: Network.savedWifiSsids.length === 0
                    text: Translation.tr("No saved networks")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                Repeater {
                    model: Network.savedWifiSsids
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.normal
                            elide: Text.ElideRight
                        }
                        RippleButton {
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                            enabled: modelData !== Network.active?.ssid
                            onClicked: page.connectNetwork(Network.wifiNetworks.find(ap => ap.ssid === modelData))
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "link"
                                color: Appearance.colors.colPrimary
                            }
                        }
                        RippleButton {
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                            onClicked: page.disconnectNetwork(modelData)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "link_off"
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                        RippleButton {
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                            onClicked: page.forgetNetwork(modelData)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "delete"
                                color: Appearance.colors.colError
                            }
                        }
                    }
                }
            }
        }
    }
}
