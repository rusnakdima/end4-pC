import QtQuick

/**
 * Keeps a user-writable control property bound to the config after the
 * control overwrites it on user input.
 *
 * A control like ConfigSwitch writes its own `checked` property when the
 * user clicks it. That imperative assignment destroys the declarative
 * `checked: Config.options.someKey` binding, so from then on the control
 * only pushes to the config and never pulls again. When the same key has a
 * control in another surface, the two copies drift apart for the rest of
 * the session.
 *
 * This element re-applies the config value whenever it changes, without
 * preventing the control from showing its own intermediate state while the
 * user drags a slider or types in a field. Place it inside the control and
 * give the control an id:
 *
 *   ConfigSwitch {
 *       id: switchItem
 *       checked: Config.options.foo
 *       onCheckedChanged: {
 *           if (checked === Config.options.foo) return;
 *           Config.options.foo = checked;
 *       }
 *       ConfigBinding {
 *           target: switchItem
 *           property: "checked"
 *           value: Config.options.foo
 *       }
 *   }
 *
 * The guard in the handler is required: re-applying the value fires the
 * change handler again, and a write there would echo back into the config.
 */
Binding {
    restoreMode: Binding.RestoreBinding
}
