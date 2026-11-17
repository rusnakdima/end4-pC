import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    property var vncStatus: ({})
    property bool statusLoaded: false
    property bool syncing: false

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true
    }

    function setOption(key, value) {
        Quickshell.execDetached(["bash", "-lc", "$HOME/.local/bin/end4pc-vnc set " + key + " " + value])
        refreshTimer.restart()
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess
        command: ["bash", "-lc", "$HOME/.local/bin/end4pc-vnc status --json"]
        stdout: StdioCollector {
            id: statusStdout
        }
        onExited: (code) => {
            page.syncing = true
            try {
                page.vncStatus = JSON.parse(statusStdout.text)
                page.statusLoaded = (code === 0)
            } catch (e) {
                page.vncStatus = ({})
                page.statusLoaded = false
            }
            syncReleaseTimer.restart()
        }
    }

    Timer {
        id: refreshTimer
        interval: 1000
        repeat: false
        onTriggered: page.refresh()
    }

    Timer {
        id: syncReleaseTimer
        interval: 500
        repeat: false
        onTriggered: page.syncing = false
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 20

        ContentSection {
            icon: "screen_share"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("VNC remote desktop")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "visibility"
                    text: Translation.tr("Interactive physical mirror")
                    checked: page.vncStatus.mirror_input === 1
                    enabled: page.statusLoaded && !page.syncing
                    onCheckedChanged: {
                        if (page.syncing || !page.statusLoaded)
                            return
                        page.setOption("mirror_input", checked ? 1 : 0)
                    }
                }
                ConfigSwitch {
                    buttonIcon: "lock"
                    text: Translation.tr("Lock session on last disconnect")
                    checked: page.vncStatus.theme_lock === 1
                    enabled: page.statusLoaded && !page.syncing
                    onCheckedChanged: {
                        if (page.syncing || !page.statusLoaded)
                            return
                        page.setOption("theme_lock", checked ? 1 : 0)
                    }
                }
                ConfigSwitch {
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Blank wallpaper while connected")
                    checked: page.vncStatus.blank_wallpaper === 1
                    enabled: page.statusLoaded && !page.syncing
                    onCheckedChanged: {
                        if (page.syncing || !page.statusLoaded)
                            return
                        page.setOption("blank_wallpaper", checked ? 1 : 0)
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer1
                text: page.statusLoaded
                    ? Translation.tr("Physical: %1\nHidden: %2\nMode: %3")
                        .arg(page.vncStatus.endpoints.mirror)
                        .arg(page.vncStatus.endpoints.hidden)
                        .arg(page.vncStatus.mode)
                    : Translation.tr("VNC module not installed, or end4pc-vnc is unavailable.")
            }
        }
    }
}
