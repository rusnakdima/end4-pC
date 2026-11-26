# WiFi Forget / Connect-Disconnect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add BT-style expandable Connect/Disconnect and Forget actions to the WiFi networks in the quick right panel.

**Architecture:** Extend the `Network` singleton with saved-profile discovery (`nmcli -t -f NAME,TYPE c show` filtered to `802-11-wireless`) and a `forgetWifiNetwork(ssid)` action, then mirror `BluetoothDeviceItem.qml`'s expandable row in `WifiNetworkItem.qml`. No new files in the runtime path; saved state is re-queried on `nmcli monitor` updates and after each action.

**Tech Stack:** QML / QtQuick (Quickshell 0.3.x), `Quickshell.Io.Process`, NetworkManager `nmcli`, bash test harness.

**Spec:** `docs/superpowers/specs/2026-11-26-wifi-forget-disconnect-design.md`

## Global Constraints

- Saved WiFi profiles are `TYPE=802-11-wireless` in `nmcli -t -f NAME,TYPE c show`. Never filter on `wifi`.
- Pass SSIDs to `nmcli` as separate argv elements; no shell interpolation.
- Reuse `Translation.tr("Connect")`, `Translation.tr("Disconnect")`, `Translation.tr("Forget")` — all locales already have them.
- Reuse `BluetoothDeviceItem.qml`'s `ActionButton` component styling and chevron Behavior.
- The waffle-style action center panel is out of scope.

## Review Focus

- A network with no saved profile: Forget must not be offered, Connect still must work. Test: `check` assertions on `Network.isWifiSaved` in Task 1's wiring test.
- Forgetting the active network: state must refresh immediately even though no scan occurs. Test: `getSavedWifiProfiles.running = true` in `forgetProc.onExited` (Task 1).
- SSIDs containing spaces or regex/shell metacharacters: must be passed as argv, not interpolated. Test: `check` on `["nmcli", "connection", "delete", ssid]` (Task 1).
- Row action after a rescan destroys the `WifiAccessPoint` object: collapse before acting. Test: `check_absent` on direct connect in `onClicked` and code review (Task 2).
- Saved profile names that differ from SSID: documented limitation, not handled. Test: no test; spec Non-goals records it.

---

### Task 1: Network service — saved profiles and forget action

**Files:**
- Modify: `services/Network.qml`
- Test: `tests/test_wifi_forget_wiring.sh` (create)

**Interfaces:**
- Consumes: existing `getNetworks` Process, `update()` driven by `nmcli monitor`, `active` property.
- Produces: `Network.savedWifiSsids` (`var`), `Network.isWifiSaved(ssid: string): bool`, `Network.forgetWifiNetwork(ssid: string): void`, `Network.disconnectWifiNetwork(ssid?: string): void`.

- [ ] **Step 1: Write the failing wiring test**

Create `tests/test_wifi_forget_wiring.sh` mirroring `tests/test_bluetooth_qml_wiring.sh`. Assertions:
  - `services/Network.qml` contains `802-11-wireless` (filter uses the correct NM type).
  - `services/Network.qml` contains `function isWifiSaved`.
  - `services/Network.qml` contains `function forgetWifiNetwork`.
  - `services/Network.qml` contains `["nmcli", "connection", "delete", ssid]` (argv, no shell).
  - `services/Network.qml` contains `getSavedWifiProfiles.running = true` (refresh hook).
  - `modules/ii/sidebarRight/wifiNetworks/WifiNetworkItem.qml` contains `onClicked: expanded = !expanded`.
  - the item contains `Translation.tr("Forget")` and `Translation.tr("Disconnect")`.
  - the item does NOT contain `onClicked: Network.connectToWifiNetwork` (direct connect removed).

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_wifi_forget_wiring.sh`
Expected: FAIL (missing functions and wiring).

- [ ] **Step 3: Implement the service changes in `services/Network.qml`**

  - Add `property var savedWifiSsids: []` near `friendlyWifiNetworks`.
  - Add `function isWifiSaved(ssid: string): bool { return !!ssid && root.savedWifiSsids.includes(ssid); }`.
  - Add `Process id: getSavedWifiProfiles`, `running: true`, command `["sh", "-c", "nmcli -t -f NAME,TYPE c show | awk -F: '$2 == \"802-11-wireless\" {print $1}'"]`, `LANG=C`/`LC_ALL=C`, `StdioCollector.onStreamFinished` splitting lines into `savedWifiSsids`.
  - Add `getSavedWifiProfiles.running = true` to `update()` and to `connectProc`'s stdout handler.
  - Add `function forgetWifiNetwork(ssid: string): void` calling `forgetProc.exec(["nmcli", "connection", "delete", ssid])`.
  - Add `Process id: forgetProc` with `onExited` re-running `getSavedWifiProfiles` and `getNetworks`.
  - Change `disconnectWifiNetwork` to accept an optional `ssid` defaulting to `active?.ssid ?? ""`.

- [ ] **Step 4: Run the wiring test and QML compile check**

Run: `bash tests/test_wifi_forget_wiring.sh && bash tests/qml-compile-check.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/Network.qml tests/test_wifi_forget_wiring.sh
git commit -m "feat(network): track saved WiFi profiles and add forget action"
```

### Task 2: Expandable WiFi row with Connect/Disconnect and Forget

**Files:**
- Modify: `modules/ii/sidebarRight/wifiNetworks/WifiNetworkItem.qml`

**Interfaces:**
- Consumes: `Network.isWifiSaved(ssid)`, `Network.forgetWifiNetwork(ssid)`, `Network.disconnectWifiNetwork(ssid)`, `Network.connectToWifiNetwork(accessPoint)` from Task 1.
- Produces: nothing external.

- [ ] **Step 1: Replace the row click with expansion and add the chevron**

Set `property bool expanded: false` and `pointingHandCursor: !expanded`, change `onClicked` from `Network.connectToWifiNetwork(wifiNetwork)` to `expanded = !expanded`, and add the rotating `keyboard_arrow_down` `MaterialSymbol` from `BluetoothDeviceItem.qml:69-77` after the security icon.

- [ ] **Step 2: Add the expanded action row**

Add an inline `ActionButton` component using `Appearance.colors.colPrimary` / `colPrimaryHover` / `colPrimaryActive` / `colOnPrimary`, then a `RowLayout` with `visible: root.expanded` and a leading `Item { Layout.fillWidth: true }`, containing:
  - Forget button: `visible: Network.isWifiSaved(root.wifiNetwork?.ssid ?? "")`, error colors (`colError` / `colErrorHover` / `colErrorActive` / `colOnError`), label `Translation.tr("Forget")`, handler collapses then calls `Network.forgetWifiNetwork(ssid)`.
  - Connect/Disconnect button: label `Translation.tr("Disconnect")` when `wifiNetwork.active`, else `Translation.tr("Connect")`; handler collapses then calls `Network.disconnectWifiNetwork(ssid)` or `Network.connectToWifiNetwork(network)`.

  Keep the existing password prompt and public-portal blocks unchanged.

- [ ] **Step 3: Verify wiring and compile**

Run: `bash tests/test_wifi_forget_wiring.sh && bash tests/qml-compile-check.sh`
Expected: PASS.

- [ ] **Step 4: Live verification**

With the shell reloaded: open the right sidebar, right-click the WiFi tile, click a saved network → Forget is visible; click Disconnect on the active network → `nmcli -g ACTIVE,SSID d w` shows it disconnected; click Forget → profile disappears from `nmcli -t -f NAME,TYPE c show`; reconnect flow and password prompt still work.

- [ ] **Step 5: Commit**

```bash
git add modules/ii/sidebarRight/wifiNetworks/WifiNetworkItem.qml
git commit -m "feat(wifi): add BT-style connect/disconnect and forget actions"
```
