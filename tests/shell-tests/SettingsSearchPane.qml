// Test-harness shim: SettingsContent loads its sibling SettingsSearchPane
// through a local import; in the hosted runner the import resolves from the
// test directory, so provide a minimal stand-in with the same public API.
import QtQuick

Item {
    property string query: ""
    signal dismissed()
}
