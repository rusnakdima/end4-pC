# Bluetooth Right-Panel Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the right-panel Bluetooth tile and dialog detect, power on, and connect Bluetooth even when Quickshell's one-shot BlueZ init failed.

**Architecture:** Two layers: a startup gate waits for `org.bluez` before launching the shell, and a QML data-layer fallback queries BlueZ via `bluetoothctl` when Quickshell's Bluetooth singleton has no adapter. `BluetoothStatus` becomes the single API that all UI consumes; live Quickshell data wins when present.

**Tech Stack:** Bash, Python 3 (stdlib only), QML/QtQuick, Quickshell 0.3.x (`Quickshell.Io.Process`), BlueZ `bluetoothctl`, `dbus-send`.

**Spec:** `docs/superpowers/specs/2026-11-23-bluetooth-right-panel-resilience-design.md`

## Global Constraints

- No new runtime dependencies: `bluetoothctl` and `dbus-send` are assumed present.
- Never patch or vendor Quickshell; all changes stay inside `end4-pC/`.
- New `scripts/` files are deployed by the existing `rsync` in `install.sh:install_qs_config` — do not add a separate copy step.
- All commands that touch BlueZ must use `bluetoothctl --timeout 2` (non-interactive one-shot mode) so a dead daemon can never hang the shell.
- The wait gate must always exit 0 so a machine with no Bluetooth hardware still boots.
- QML must keep compiling with `tests/qml-compile-check.sh`; no new QML modules beyond existing imports.

## Review Focus

- **No adapter at boot / BlueZ starts late** — gate must not block login forever. Test: `tests/test_wait_for_bluez.sh` timeout case.
- **`bluetoothctl` missing or failing** — helper degrades to `available: false`, never throws into QML. Test: `tests/test_bluez_state.py` missing-controller case.
- **Live Quickshell data recovers** — unified API must prefer live data and stop polling. Test: Task 3 Step 3 asserts `quickshellLive` wins in the property expressions; Task 5 Step 3 covers the restart case on the live shell.
- **Fallback device objects must render in the dialog** — `BluetoothDeviceItem` must not require a concrete `BluetoothDevice`. Test: Task 4 compile check + manual dialog check.
- **A stray discovery toggle must not fight the fallback** — night-light page no longer starts/stops BT discovery. Test: Task 4 grep assertion.

---

### Task 1: BlueZ startup gate

**Files:**
- Create: `scripts/bluetooth/wait-for-bluez.sh`
- Modify: `install.sh:323-347` (`patch_hyprland_autostart`)
- Test: `tests/test_wait_for_bluez.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/bluetooth/wait-for-bluez.sh` (exit 0 always), honours `END4PC_BT_WAIT_SECONDS` override (default `10`) for tests.

- [ ] **Step 1: Write the failing test** `tests/test_wait_for_bluez.sh`

`bash tests/test_wait_for_bluez.sh`. It builds a temp dir with a fake `dbus-send` on `PATH` that writes one line to `$STUB_LOG` per invocation and exits with code from `STUB_FAIL_FIRST_N`. Assert three cases with `END4PC_BT_WAIT_SECONDS=0.6`: (a) stub always succeeds → script exits 0 with exactly 1 call; (b) stub fails first 2 calls then succeeds → exits 0 with 3 calls; (c) stub always fails → exits 0 with at least 3 calls (bounded by timeout). Use the same `check`/`fail` helper style as `tests/test_cava_source.sh`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_wait_for_bluez.sh`
Expected: FAIL — script file missing.

- [ ] **Step 3: Implement `scripts/bluetooth/wait-for-bluez.sh`**

Bash script: `set -u`; read `END4PC_BT_WAIT_SECONDS` (default 10); loop with `0.2` s sleep calling
`dbus-send --system --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.GetNameOwner string:org.bluez`
with stdout/stderr suppressed; exit 0 on first success and after the deadline regardless. Make it executable (`chmod +x`).

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_wait_for_bluez.sh`
Expected: PASS (all three cases OK).

- [ ] **Step 5: Patch the Hyprland autostart generator in `install.sh`**

In `patch_hyprland_autostart()`, keep the existing legacy regex, but change its replacement so the emitted line is equivalent to:
`hl.exec_cmd("bash -c '\"$HOME/.config/quickshell/end4-pC/scripts/bluetooth/wait-for-bluez.sh\" && exec qs -n -p <original-path>'")`.
Add a second regex+substitution for the already-patched `hl.exec_cmd("qs -n -p <path>")` form so re-running install upgrades it instead of leaving it unwrapped. Both substitutions must be idempotent.

- [ ] **Step 6: Verify the patch logic offline**

Run: `python3 - <<'PY' ...` with a temp file containing both the legacy and the current `qs -n -p` lines, invoking only the embedded Python patch block; assert the resulting file contains `wait-for-bluez.sh` exactly once per line and still contains `exec qs -n -p`. Expected: assertions pass.

- [ ] **Step 7: Commit**

`git add scripts/bluetooth/wait-for-bluez.sh install.sh tests/test_wait_for_bluez.sh`
`git commit -m "fix(bluetooth): wait for BlueZ before launching the shell"`

---

### Task 2: BlueZ state/action helper

**Files:**
- Create: `scripts/bluetooth/bluez-state.py`
- Test: `tests/test_bluez_state.py`

**Interfaces:**
- Consumes: `bluetoothctl` on `PATH`.
- Produces: `python3 bluez-state.py [--query]` prints one JSON object:
  `{"available": bool, "enabled": bool, "discovering": bool, "devices": [{"address": str, "name": str, "icon": str, "paired": bool, "connected": bool, "battery": float, "batteryAvailable": bool}]}`.
  Action flags `--power on|off`, `--discover start|stop`, `--connect ADDR`, `--disconnect ADDR`, `--pair ADDR`, `--forget ADDR` run the matching `bluetoothctl` command and then print the same query JSON. Exit 0 even when BlueZ is unavailable (then `available: false`, empty devices).

- [ ] **Step 1: Write the failing test** `tests/test_bluez_state.py`

`unittest` test (discovered by `tests/run-python-tests.sh`). Create a temp dir with a fake `bluetoothctl` executable that prints canned `show` / `devices` / `info` output based on argv and logs argv to `$BT_STUB_LOG`. Assertions: (a) query with one connected, one paired-unconnected device returns `available/enabled` true and the two devices with correct `paired`, `connected`, `icon`, `battery` (0.75) and `name` from `Alias`; (b) `show` with no `Controller` line returns `available: false` and empty devices; (c) `--power on --connect AA:BB` logs exactly `['--timeout', '2', 'power', 'on']` and `['--timeout', '2', 'connect', 'AA:BB']` and still prints valid JSON.

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest discover -s tests -p 'test_bluez_state.py' -v`
Expected: FAIL — helper file missing.

- [ ] **Step 3: Implement `scripts/bluetooth/bluez-state.py`**

Python 3 stdlib only. Use `subprocess.run(["bluetoothctl", "--timeout", "2", *args], capture_output=True, text=True, timeout=5)` with `FileNotFoundError`/`TimeoutExpired` treated as unavailable. Parse `show` for `Controller`, `Powered: yes`, `Discovering: yes`; parse `devices` lines with `^Device\s+(\S+)\s*(.*)$`; parse each `info <addr>` for `Alias:` (fallback `Name:`), `Icon:`, `Paired: yes`, `Connected: yes`, and `Battery Percentage: 0x.. (N)` → `battery = N/100`, `batteryAvailable = true`. Actions map to `power on|off`, `scan on|off`, `connect ADDR`, `disconnect ADDR`, `pair ADDR`, `remove ADDR` (forget). Always finish with the query JSON on stdout. Keep stdout single-line JSON so QML can `JSON.parse` it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m unittest discover -s tests -p 'test_bluez_state.py' -v`
Expected: PASS.

- [ ] **Step 5: Commit**

`git add scripts/bluetooth/bluez-state.py tests/test_bluez_state.py`
`git commit -m "feat(bluetooth): add bluetoothctl state/action helper"`

---

### Task 3: Unified BluetoothStatus API

**Files:**
- Modify: `services/BluetoothStatus.qml` (whole file rewrite; keep existing sorting and `isConnected` semantics)

**Interfaces:**
- Consumes: Task 2's helper JSON, invoked at `Quickshell.shellPath("scripts/bluetooth/bluez-state.py")`.
- Produces: `available`, `enabled`, `discovering` (bool); `devices` (list of device objects); existing `connectedDevices`, `pairedButNotConnectedDevices`, `unpairedDevices`, `friendlyDeviceList`, `connectedBatteryDevices`, `firstActiveDevice`, `activeDeviceCount`, `connected`, `primaryConnectedDevice`, `primaryBatteryDevice`; `isConnected(device)`, `hasBattery(device)`, `sortFunction(a,b)`; new `setPower(on: bool)`, `startDiscovery()`, `stopDiscovery()`, `runAction(action: string, address: string)`; `togglePower()` updated to call `setPower`.

- [ ] **Step 1: Write the failing check**

Run: `grep -q 'startDiscovery' services/BluetoothStatus.qml`
Expected: FAIL (no such symbol yet).

- [ ] **Step 2: Implement the data layer in `services/BluetoothStatus.qml`**

Keep `pragma Singleton`/`pragma ComponentBehavior: Bound`, imports plus `Quickshell` and `Quickshell.Io`. Define:
  - `property var fallbackState: ({})` and `readonly property bool quickshellLive: Bluetooth.adapters.values.length > 0`.
  - `Process` id `stateProc` with `command: ["python3", "-I", Quickshell.shellPath("scripts/bluetooth/bluez-state.py")]`, `stdout: SplitParser { onRead: line => { const parsed = JSON.parse(line); if (signatureChanged) root.fallbackState = parsed } }`. Compute a signature from `available/enabled/discovering` and each device's `address/paired/connected/battery` so unchanged polls do not rebind the UI.
  - `Timer` id `pollTimer` with `interval: 5000`, `repeat: true`, `running: !root.quickshellLive`, `onTriggered: stateProc.running = true`.
  - `Component.onCompleted: stateProc.running = true`.
  - `function runAction(action, address)` builds `[python3, -I, script, ...flags]` and assigns to `stateProc.command`, running it; on `onExited` restore the query command and set `stateProc.running = true` once.
  - Shape fallback devices in JS: each JSON device becomes an object with the same field names and `connect`/`disconnect`/`pair`/`forget` methods that call `root.runAction("<name>", address)`. Keep a stable map keyed by address so object identity survives a poll when fields are unchanged.
  - Unified properties: `available = quickshellLive || fallbackState.available === true`; `enabled = quickshellLive ? (Bluetooth.defaultAdapter?.enabled ?? false) : (fallbackState.enabled === true)`; `discovering = quickshellLive ? (Bluetooth.defaultAdapter?.discovering ?? false) : (fallbackState.discovering === true)`; `devices = quickshellLive ? Bluetooth.devices.values : shapedFallbackDevices`.
  - Rewrite all derived lists to filter over `root.devices` instead of `Bluetooth.devices.values`, preserving the existing sort and `isConnected` logic verbatim.

- [ ] **Step 3: Verify compile and symbol presence**

Run: `bash tests/qml-compile-check.sh` then `grep -q 'startDiscovery' services/BluetoothStatus.qml`
Expected: compile PASS, grep success.

- [ ] **Step 4: Commit**

`git add services/BluetoothStatus.qml`
`git commit -m "feat(bluetooth): add Quickshell/Bluetooth fallback data layer"`

---

### Task 4: Switch UI consumers to the unified API

**Files:**
- Modify: `modules/ii/sidebarRight/SidebarRightContent.qml:644-657`
- Modify: `modules/ii/sidebarRight/bluetoothDevices/BluetoothDialog.qml:33-42,69`
- Modify: `modules/ii/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml:10`
- Modify: `modules/waffle/actionCenter/bluetooth/BluetoothControl.qml:19-28,54-67,74,143-147`
- Modify: `modules/waffle/actionCenter/nightLight/NightLightControl.qml:6,19-25`

**Interfaces:**
- Consumes: Task 3's `BluetoothStatus.setPower`, `startDiscovery`, `stopDiscovery`, `discovering`, `enabled`, `available`.
- Produces: no new public API.

- [ ] **Step 1: Record the baseline**

Run: `grep -R -n 'Bluetooth.defaultAdapter' modules/ii/sidebarRight modules/waffle/actionCenter`
Expected: at least 5 matches are listed — this is the direct adapter access Task 4 must eliminate. (This is a refactor task, so the checkable baseline is the match count, not a failing test.)

- [ ] **Step 2: Replace direct adapter access**

  - `SidebarRightContent.qml`: in the Bluetooth `ToggleDialog.onShownChanged`, replace `adapter.enabled = true; adapter.discovering = true` with `BluetoothStatus.setPower(true); BluetoothStatus.startDiscovery()`, and the hidden branch with `BluetoothStatus.stopDiscovery()`. Remove the local `const adapter` and `if (!adapter) return` guard.
  - `BluetoothDialog.qml`: `visible: !(Bluetooth.defaultAdapter?.discovering ?? false)` → `visible: !BluetoothStatus.discovering`, and the progress bar's `visible` → `BluetoothStatus.discovering`. Change delegate `required property BluetoothDevice modelData` to `required property var modelData`.
  - `BluetoothDeviceItem.qml`: change `required property var device` — leave as-is if already `var`; ensure no `BluetoothDevice` typing remains.
  - `BluetoothControl.qml`: switch `checked: BluetoothStatus.enabled`; `onCheckedChanged` → `BluetoothStatus.setPower(checked)` then `startDiscovery()`/`stopDiscovery()`; progress bar `shown: BluetoothStatus.discovering`; rescan button `enabled: !BluetoothStatus.discovering && BluetoothStatus.enabled` and `onClicked: BluetoothStatus.startDiscovery()`. Remove `Component.onCompleted/onDestruction` discovery blocks (the dialog/panel owns discovery now). The `import Quickshell.Bluetooth` may remain harmlessly or be dropped.
  - `NightLightControl.qml`: delete the `Component.onCompleted`/`onDestruction` block that starts/stops Bluetooth discovery and drop the now-unused `import Quickshell.Bluetooth`.

- [ ] **Step 3: Verify no direct adapter access remains in these consumers**

Run: `! grep -R -q 'Bluetooth.defaultAdapter' modules/ii/sidebarRight modules/waffle/actionCenter`
Expected: success (no matches).

- [ ] **Step 4: Compile all QML**

Run: `bash tests/qml-compile-check.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

`git add modules/ii/sidebarRight modules/waffle/actionCenter`
`git commit -m "fix(bluetooth): route right-panel and action-center BT UI through BluetoothStatus"`

---

### Task 5: End-to-end verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full offline test suites**

Run:
`bash tests/test_wait_for_bluez.sh`
`python3 -m unittest discover -s tests -p 'test_bluez_state.py' -v`
`bash tests/qml-compile-check.sh`
Expected: all PASS.

- [ ] **Step 2: Validate helper against live BlueZ**

Run: `python3 -I scripts/bluetooth/bluez-state.py`
Expected: JSON with `"available": true`, `"enabled": true`, and the paired devices from `bluetoothctl devices` present with correct `name`/`paired`/`connected`.

- [ ] **Step 3: Manual right-panel check on the live shell**

With the shell restarted (or reloaded), open the right sidebar → Quick toggles → right-click the Bluetooth tile (or open the Bluetooth dialog). Expected: adapter reads as on, the device list populates, and Connect/Disconnect change state. Then run `systemctl restart bluetooth` in a root shell while the shell stays up; within ~5 s the panel should reflect the new state via the fallback.

- [ ] **Step 4: Commit any verification-driven fixes**

Only if Step 3 exposes a defect: fix it in the owning task's files and amend that task's commit rather than creating a catch-all commit.
