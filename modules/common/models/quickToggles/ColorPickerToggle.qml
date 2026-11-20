import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Color picker")
    hasStatusText: false
    toggled: false
    icon: "colorize"

    mainAction: () => {
        GlobalStates.sidebarRightOpen = false;
        delayedActionTimer.start();
    }
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: {
            const toAdvancedPaste = (Config.options?.advancedPaste?.colorPickerOpensPopup ?? true)
                ? " && sleep 0.1 && qs -c end4-pC ipc call advancedPaste open"
                : "";
            Quickshell.execDetached(["bash", "-c", `hyprpicker -a${toAdvancedPaste}`]);
        }
    }

    tooltipText: Translation.tr("Color picker")
}
