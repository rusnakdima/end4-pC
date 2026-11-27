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

## Categories style

Settings has a fourth panel style, `categories`, alongside `default`, `minimal`
and `dashboard`. Select it under **Settings → Appearance → Settings panel
style**. The other styles and every page QML are unchanged.

Pages are grouped into five categories defined in `services/SettingsPages.qml`:

- **Network & internet** — Wi-Fi
- **Connected devices** — Bluetooth, VNC, Cast, Projection
- **Personalization** — Quick settings, Appearance, Desktop, Bar, Interface, Dock & Lock
- **System** — Tools, Advanced paste, General, Default apps, Keyboard, Services, Hyprland/Niri pages
- **About** — About

Wide windows show a category rail, the pages in the selected category and one
lazy page pane. Narrow windows replace the page list with a back button and a
`category › page` breadcrumb. Deep-links (including the Wi-Fi/Bluetooth gear
buttons) select the right category and page automatically, and search results
show the category path above the page name when this style is active.
