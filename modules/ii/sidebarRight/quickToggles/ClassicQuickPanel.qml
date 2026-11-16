import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.classicStyle

AbstractQuickPanel {
    id: root
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: buttonGroup.implicitWidth
    implicitHeight: buttonGroup.implicitHeight
    color: "transparent"

    ButtonGroup {
        id: buttonGroup
        spacing: 5
        padding: 5
        // The section above paints the card (the sliders and notification
        // cards do the same), so the panel must not paint a second one.
        color: "transparent"

        NetworkToggle {
            altAction: () => {
                root.openWifiDialog();
            }
        }
        BluetoothToggle {
            altAction: () => {
                root.openBluetoothDialog();
            }
        }
        HotspotToggle {
            altAction: () => {
                root.openHotspotDialog();
            }
        }
        NightLight {}
        LiveWallpaperToggle {}
        GameMode {}
        IdleInhibitor {}
        EasyEffectsToggle {}
        CloudflareWarp {}
    }
}
