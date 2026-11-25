import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Waydroid")
    statusText: Waydroid.statusText
    hasStatusText: true
    tooltipText: Translation.tr("Waydroid session | Left-click start/stop, right-click full UI")
    icon: "android"

    toggled: Waydroid.session === "RUNNING" || Waydroid.container === "RUNNING"
    available: !Waydroid.busy
    mainAction: () => {
        if (Waydroid.session === "RUNNING" || Waydroid.container === "RUNNING")
            Waydroid.stop()
        else
            Waydroid.start()
    }
    hasMenu: true
}
