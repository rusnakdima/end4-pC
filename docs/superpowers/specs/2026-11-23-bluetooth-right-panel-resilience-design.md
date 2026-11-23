# Bluetooth Right-Panel Resilience — Design

## Intent

The right-hand quick panel does not detect that Bluetooth is on even though the
system Bluetooth manager can see the adapter and connect/switch devices. The
root cause is upstream: Quickshell's `Bluez::init()` connects to `org.bluez`
exactly once when the shell process starts; if BlueZ is absent or transiently
unavailable at that moment, the integration stays dead for the process
lifetime (`quickshell#1201`). This repo cannot patch Quickshell C++, so the fix
has two layers that live entirely in `end4-pC/`.

## Goals

- Prevent the one-shot init failure at login by making the shell wait briefly
  for `org.bluez` before launching.
- Make the right-panel BT tile and BT dialog detect adapter state, power it on,
  start discovery, and connect/pair devices even when Quickshell's Bluetooth
  singleton is dead.
- Keep the bar widget, `BluetoothPopup`, and both quick-toggle styles working
  unchanged by centralising the fix in `BluetoothStatus`.

## Non-goals

- Patching or vendoring Quickshell.
- Adding a new dependency; `bluetoothctl` (bluez-utils) and `dbus-send` (dbus)
  are expected to be present.
- Changing the visual design of the BT tile or dialog.

## Constraints

- Quickshell 0.3.x: `Quickshell.Bluetooth` exposes no generic D-Bus access, so
  the fallback must use CLI helpers via `Quickshell.Io.Process`.
- `Bluetooth.devices` and `BluetoothAdapter.devices` contain all tracked
  devices, not only connected ones (verified against Quickshell source), so
  the existing connected/paired/unpaired filters stay valid.
- Shell config is deployed by the repo's `rsync` in `install.sh`; any new
  script under `scripts/` is picked up automatically.

## Approaches (considered and chosen)

1. Wait for BlueZ before launching the shell — small, fixes the common trigger,
   but not a late dongle/demon restart. **Chosen as layer 1.**
2. QML data-layer fallback via `bluetoothctl` — works after late BlueZ changes,
   but larger. **Chosen as layer 2.**
3. Both. **Approved by the user.**

Rejected: auto-restarting the shell when BlueZ appears (disruptive and prone to
loops), and patching Quickshell itself (not possible from this repo).

## Design

### Layer 1 — startup gate

`scripts/bluetooth/wait-for-bluez.sh` polls the system bus for an `org.bluez`
name owner with a bounded timeout (~10 s) and always exits 0. `install.sh`'s
`patch_hyprland_autostart()` wraps the generated `qs -n -p …` autostart command
with this script, and is made idempotent so an already-patched line is upgraded
rather than duplicated.

### Layer 2 — QML fallback

`scripts/bluetooth/bluez-state.py` has a query mode that prints JSON
(`available`, `enabled`, `discovering`, `devices[]`) parsed from
`bluetoothctl show/devices/info`, and action modes (`--power`, `--discover`,
`--connect`, `--disconnect`, `--pair`, `--forget`) that run the corresponding
command and re-emit fresh state.

`services/BluetoothStatus.qml` runs the helper with a `Process` and a ~5 s
`Timer` while Quickshell reports no adapter, then exposes a single API:
`available`, `enabled`, `discovering`, `devices`/the three filtered lists,
`isConnected()`, `togglePower()`, `setPower()`, `startDiscovery()`,
`stopDiscovery()`. Live Quickshell data wins whenever present; fallback objects
carry the same fields and action methods as `BluetoothDevice`.

Consumers that reached into `Bluetooth.defaultAdapter` directly switch to the
unified API: `SidebarRightContent.qml`, `BluetoothDialog.qml`,
`BluetoothControl.qml`. The stray Bluetooth discovery in
`NightLightControl.qml` is removed. BT dialog delegates relax their
`BluetoothDevice` typing to `var` so fallback objects render.

## Risks / tradeoffs

- If no adapter exists at all, the BT toggle is shown as off instead of being
  hidden — acceptable, because otherwise BT can never be enabled from the UI.
- `bluetoothctl scan on` blocks for the helper's timeout (~2 s); acceptable for
  an explicit rescan action.
- The fallback polls every ~5 s only while Quickshell sees no adapter, so the
  normal path pays no extra cost.

## Verification

- `tests/test_wait_for_bluez.sh` stubs `dbus-send` to cover success, delayed
  success, and timeout.
- `tests/test_bluez_state.py` stubs `bluetoothctl` and asserts the parsed JSON
  and emitted action commands.
- `tests/qml-compile-check.sh` covers all QML edits.
- Manual: on a live shell with BT on, open the right-panel BT dialog; the
  adapter reads on, devices populate, Connect/Disconnect work. Restart
  `bluetoothd` while the shell runs to exercise the fallback path.
