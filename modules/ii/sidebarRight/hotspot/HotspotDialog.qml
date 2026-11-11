import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    property bool passphraseRevealed: false
    property bool settingsExpanded: false
    property bool clientsExpanded: false

    WindowDialogTitle {
        text: Translation.tr("Hotspot")
    }

    // Status — band format while active
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            text: Hotspot.active ? "wifi_tethering" : "portable_wifi_off"
            iconSize: Appearance.font.pixelSize.larger
            color: Hotspot.error !== "" && !Hotspot.active
                ? Appearance.colors.colError
                : Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            color: Hotspot.error !== "" && !Hotspot.active
                ? Appearance.colors.colError
                : Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
            text: !Hotspot.active && Hotspot.error !== ""
                ? Hotspot.error
                : Hotspot.active
                    ? `${Translation.tr("On")} · ${Hotspot.channel <= 14 ? "2.4 GHz" : "5 GHz"} · ch ${Hotspot.channel} · ${Hotspot.clients.length} ${Hotspot.clients.length === 1 ? Translation.tr("Client") : Translation.tr("Clients")} · ${Hotspot.uplink}`
                    : Translation.tr("Off")
        }
    }

    // Settings — hidden behind an expandable block
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Item {
            id: settingsHeader
            Layout.fillWidth: true
            implicitHeight: settingsHeaderRow.implicitHeight

            RowLayout {
                id: settingsHeaderRow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8

                MaterialSymbol {
                    text: "settings"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    font.weight: 600
                    color: Appearance.colors.colOnSurfaceVariant
                    text: Translation.tr("Settings")
                }
                Item {
                    Layout.fillWidth: true
                }
                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    rotation: root.settingsExpanded ? 180 : 0
                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsExpanded = !root.settingsExpanded
            }
        }

        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: root.settingsExpanded ? settingsContent.implicitHeight : 0
            visible: implicitHeight > 0

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                id: settingsContent
                width: parent.width
                spacing: 4

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Network name")
                    text: Config.options.hotspot.ssid
                    onTextChanged: Qt.callLater(() => {
                        Config.options.hotspot.ssid = text;
                    })
                }

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Password")
                    echoMode: root.passphraseRevealed ? TextInput.Normal : TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                    text: Config.options.hotspot.passphrase
                    onTextChanged: Qt.callLater(() => {
                        Config.options.hotspot.passphrase = text;
                    })

                    MaterialSymbol {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        iconSize: Appearance.font.pixelSize.normal
                        fill: root.passphraseRevealed ? 1 : 0
                        text: root.passphraseRevealed ? "visibility_off" : "visibility"
                        color: Appearance.colors.colOnSurfaceVariant

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.passphraseRevealed = !root.passphraseRevealed
                        }
                    }
                }

                ToolbarTabBar {
                    id: bandTabs
                    tabButtonList: [
                        { id: "auto", name: Translation.tr("Auto"), icon: "autorenew" },
                        { id: "band24", name: "2.4 GHz", icon: "cell_tower" },
                        { id: "band5", name: "5 GHz", icon: "signal_cellular_alt" }
                    ]
                    currentIndex: Config.options.hotspot.channel === 0 ? 0
                        : (Config.options.hotspot.channel <= 14 ? 1 : 2)
                    onCurrentIndexChanged: {
                        const ch = Config.options.hotspot.channel;
                        if (currentIndex === 0) { if (ch !== 0) Config.options.hotspot.channel = 0; }
                        else if (currentIndex === 1) { if (!(ch >= 1 && ch <= 14)) Config.options.hotspot.channel = 6; }
                        else { if (!(ch >= 36 && ch <= 165)) Config.options.hotspot.channel = 48; }
                    }
                }

                ConfigSpinBox {
                    visible: bandTabs.currentIndex !== 0
                    icon: "settings_input_antenna"
                    text: bandTabs.currentIndex === 1 ? `${Translation.tr("Channel")} · 2.4 GHz` : `${Translation.tr("Channel")} · 5 GHz`
                    value: Config.options.hotspot.channel
                    from: bandTabs.currentIndex === 1 ? 1 : 36
                    to: bandTabs.currentIndex === 1 ? 14 : 165
                    stepSize: 1
                    onValueChanged: Qt.callLater(() => {
                        if (visible && value !== Config.options.hotspot.channel)
                            Config.options.hotspot.channel = value;
                    })
                }
            }
        }
    }

    // Clients — expandable, shown only while the AP is up
    ColumnLayout {
        Layout.fillWidth: true
        visible: Hotspot.active
        spacing: 6

        Item {
            id: clientsHeader
            Layout.fillWidth: true
            implicitHeight: clientsHeaderRow.implicitHeight

            RowLayout {
                id: clientsHeaderRow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8

                MaterialSymbol {
                    text: "devices"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    font.weight: 600
                    color: Appearance.colors.colOnSurfaceVariant
                    text: Hotspot.clients.length > 0
                        ? `${Translation.tr("Clients")} · ${Hotspot.clients.length}`
                        : Translation.tr("Clients")
                }
                Item {
                    Layout.fillWidth: true
                }
                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    rotation: root.clientsExpanded ? 180 : 0
                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clientsExpanded = !root.clientsExpanded
            }
        }

        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: root.clientsExpanded ? clientsContent.implicitHeight : 0
            visible: implicitHeight > 0

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                id: clientsContent
                width: parent.width
                spacing: 4

                StyledText {
                    visible: Hotspot.clients.length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("No clients yet")
                }

                ListView {
                    id: clientsView
                    Layout.fillWidth: true
                    implicitHeight: Math.min(contentHeight, 160)
                    clip: true
                    spacing: 2

                    model: ScriptModel {
                        values: Hotspot.clients
                    }

                    delegate: RowLayout {
                        required property var modelData
                        width: clientsView.width
                        spacing: 8

                        StyledText {
                            Layout.preferredWidth: 110
                            color: Appearance.colors.colOnSurfaceVariant
                            text: modelData.ip !== "" ? modelData.ip : Translation.tr("—")
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnSurfaceVariant
                            text: modelData.host !== "" ? modelData.host : modelData.mac
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            id: copyIpIcon
                            visible: modelData.ip !== ""
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 4
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurfaceVariant
                            text: "content_copy"

                            Timer {
                                id: copyIpTimer
                                interval: 1500
                                repeat: false
                                onTriggered: copyIpIcon.text = "content_copy"
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.clipboardText = modelData.ip;
                                    copyIpIcon.text = "check";
                                    copyIpTimer.restart();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Hotspot.active ? Translation.tr("Stop") : Translation.tr("Start")
            enabled: !Hotspot.busy
            onClicked: Hotspot.toggle()
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
