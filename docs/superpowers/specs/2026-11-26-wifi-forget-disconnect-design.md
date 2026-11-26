# WiFi Forget / Connect-Disconnect — Design

## Intent

The WiFi dialog opened from the quick right panel's WiFi tile should expose the
same per-network actions as the Bluetooth menu: disconnect the active network
and forget a saved network.

## Goals

1. Clicking a WiFi network expands its row (BT-style) to reveal actions.
2. Connect/Disconnect toggles the active network, preserving the password flow.
3. Forget deletes the saved NetworkManager profile for that SSID.
4. Saved/unsaved state follows `nmcli` live.

## Non-goals

- The waffle-style action center panel (already has Connect/Disconnect; separate
  design language).
- An "Always connect" equivalent: `nmcli dev wifi connect` already saves a
  profile.
- Profiles whose NAME differs from their SSID (pre-existing manually named
  profiles). The existing code already assumes NAME == SSID.

## Constraints

- NetworkManager reports WiFi profiles with `TYPE=802-11-wireless`, **not**
  `wifi` (verified with nmcli 1.58 on this machine).
- SSIDs are passed to `nmcli` as argv elements, never shell-interpolated.
- Reuse existing translations: `Connect`, `Disconnect`, `Forget` already exist
  in all 14 locale files.
- Follow `BluetoothDeviceItem.qml`'s inline `ActionButton` styling and chevron.

## Approaches

- **A (chosen):** click toggles expansion; actions live inside the expanded
  row. Matches the BT menu exactly; changes the previous click-to-connect
  behavior, which the user explicitly accepted.
- **B:** keep click-to-connect; a separate chevron expands the actions. Less
  regression, but inconsistent with the BT menu.
- **C:** always-visible action buttons. Denser rows, no expansion animation.
