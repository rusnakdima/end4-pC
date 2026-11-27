# Settings pages: Wi-Fi and Bluetooth

`Wi-Fi` (`WifiConfig.qml`) and `Bluetooth` (`BluetoothConfig.qml`) are regular
Settings pages registered in `services/SettingsPages.qml`. They use the same
`ContentPage`/`ContentSection` cards as the rest of Settings and read directly
from `Network` and `BluetoothStatus`, so they stay in sync with the quick
toggles and the right-pane dialogs.

## Search

`services/SettingsSearchIndex.qml` gives these pages extra keywords: searching
for "network", "wireless" or "wifi" finds Wi-Fi, and "bluetooth" or "pair"
finds Bluetooth. No search UI behavior changed.

## Right-pane redirect

Each Wi-Fi/Bluetooth quick tile (classic and Android styles) has a small gear
button. It sets `GlobalStates.settingsTarget = { page: "wifi" }` (or
`"bluetooth"`) and `GlobalStates.settingsOpen = true`, which reuses the
existing Settings deep-link. The tile's primary click still toggles the
adapter, and right-click still opens the existing network/Bluetooth dialog.
