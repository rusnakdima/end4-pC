import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay
import qs.modules.ii.sidebarRight.volumeMixer

StyledOverlayWidget {
    id: root
    minimumWidth: 300
    minimumHeight: 380

    contentItem: OverlayBackground {
        radius: root.contentRadius
        property real padding: 6

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: parent.padding
            }
            spacing: 8

            SecondaryTabBar {
                id: tabBar

                currentIndex: Persistent.states.overlay.volumeMixer.tabIndex
                onCurrentIndexChanged: {
                    Persistent.states.overlay.volumeMixer.tabIndex = tabBar.currentIndex;
                }

                SecondaryTabButton {
                    buttonIcon: "media_output"
                    buttonText: Translation.tr("Output")
                }
                SecondaryTabButton {
                    buttonIcon: "mic"
                    buttonText: Translation.tr("Input")
                }
                SecondaryTabButton {
                    buttonIcon: "speaker_group"
                    buttonText: Translation.tr("Devices")
                }
            }
            SwipeView {
                id: swipeView
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: Persistent.states.overlay.volumeMixer.tabIndex
                onCurrentIndexChanged: {
                    Persistent.states.overlay.volumeMixer.tabIndex = swipeView.currentIndex;
                }
                clip: true

                PaddedVolumeDialogContent { 
                    isSink: true 
                }
                PaddedVolumeDialogContent { 
                    isSink: false 
                }
                DevicesContent { }
            }
        }
    }

    /**
     * The pavucontrol device + configuration content (shared component),
     * wrapped in a flickable so the 300 px overlay widget scrolls.
     *
     * Built through a Loader: opening the overlay only pays for the two
     * volume pages, and the Devices page materializes on the first visit
     * (a direct jump to tab 3, or one step of preloading when the user
     * opens Input) — by then the pactl data layer is long warm.
     */
    component DevicesContent: Item {
        id: devicesPage
        readonly property bool wantPanel: tabBar.currentIndex >= 2 || swipeView.currentIndex >= 1

        Loader {
            id: devicesLoader
            anchors.fill: parent
            active: devicesPage.wantPanel
            sourceComponent: Flickable {
                id: devicesFlick
                clip: true
                property real padding: 12
                contentHeight: devicesPanel.implicitHeight + padding * 2
                contentWidth: width

                AudioDevicesPanel {
                    id: devicesPanel
                    x: devicesFlick.padding
                    y: devicesFlick.padding
                    width: devicesFlick.width - devicesFlick.padding * 2
                }
            }
        }
    }

    component PaddedVolumeDialogContent: Item {
        id: paddedVolumeDialogContent
        property alias isSink: volDialogContent.isSink
        property real padding: 12
        implicitWidth: volDialogContent.implicitWidth + padding * 2
        implicitHeight: volDialogContent.implicitHeight + padding * 2

        VolumeDialogContent {
            id: volDialogContent
            anchors {
                fill: parent
                margins: paddedVolumeDialogContent.padding
            }
        }
    }
}
