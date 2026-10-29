import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter
import qs.modules.waffle.actionCenter.wifi

ActionCenterToggleButton {
    toggleModel: NetworkToggle {}
    name: toggleModel.statusText
    icon: WIcons.internetIcon
    menu: Component {
        WifiControl {}
    }
}
