import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Hotspot")
    statusText: Hotspot.active
        ? (Hotspot.ssid + (Hotspot.clients.length ? " · " + Hotspot.clients.length : ""))
        : (Hotspot.error !== "" ? Hotspot.error : "")
    hasStatusText: true
    tooltipText: Translation.tr("Hotspot access point | Right-click to manage")
    icon: "wifi_tethering"

    toggled: Hotspot.active
    available: !Hotspot.busy
    mainAction: () => Hotspot.toggle()
    hasMenu: true
}
