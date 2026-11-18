import QtQuick
import qs.services

ConfigSwitch {
    id: root

    required property string optionKey
    property bool fallback: false

    checked: HyprlandOptions.asBool(HyprlandOptions.get(root.optionKey, root.fallback))

    // checked is self-assigned by ConfigSwitch on click; without this the
    // switch stops following an external configurator reload or a change
    // made from the dashboard's read-through control.
    Binding {
        target: root
        property: "checked"
        value: HyprlandOptions.asBool(HyprlandOptions.get(root.optionKey, root.fallback))
        restoreMode: Binding.RestoreBinding
    }

    // Only a real user click applies the option. Initial binding evaluation
    // and external config reloads must never write back to the compositor.
    onUserToggled: (value) => {
        HyprlandOptions.apply(root.optionKey, value)
    }
}
