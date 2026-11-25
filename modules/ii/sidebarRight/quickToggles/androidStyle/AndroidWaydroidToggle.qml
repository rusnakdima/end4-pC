import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets

AndroidQuickToggleButton {
    id: root

    toggleModel: WaydroidToggle {}

    onOpenMenu: Waydroid.openFullUI()
}
