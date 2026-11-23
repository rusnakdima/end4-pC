pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

/**
 * Single Bluetooth data layer for the whole shell.
 *
 * Quickshell's BlueZ integration connects to org.bluez once at process start;
 * if BlueZ is unavailable at that moment, Bluetooth.adapters stays empty for
 * the rest of the shell's lifetime (quickshell#1201). When that happens we
 * fall back to the bluetoothctl CLI via scripts/bluetooth/bluez-state.py.
 * Live Quickshell data always wins, so the normal path pays no polling cost.
 */
Singleton {
    id: root

    readonly property bool quickshellLive: Bluetooth.adapters.values.length > 0

    property var fallbackState: ({})
    property var shapedFallbackDevices: []
    property var deviceCache: ({})
    property string fallbackSignature: ""
    // The helper has been heard from at least once. Availability must not
    // depend on a successful query: when BlueZ is fully down the BT toggle is
    // still shown, just off (the agreed tradeoff), so the user can act on it.
    property bool helperRan: false
    readonly property string helperScript: Quickshell.shellPath("scripts/bluetooth/bluez-state.py")

    readonly property bool available: root.quickshellLive || root.helperRan || root.fallbackState.available === true
    readonly property bool enabled: root.quickshellLive
        ? (Bluetooth.defaultAdapter?.enabled ?? false)
        : (root.fallbackState.enabled === true)
    readonly property bool discovering: root.quickshellLive
        ? (Bluetooth.defaultAdapter?.discovering ?? false)
        : (root.fallbackState.discovering === true)

    readonly property var devices: root.quickshellLive
        ? Bluetooth.devices.values
        : root.shapedFallbackDevices

    // BlueZ can leave Device1.Connected false when a device reconnects on its
    // own, while audio, AVRCP and battery reporting are all live
    // (https://github.com/bluez/bluez/issues/2485). Battery1 is only exported
    // while a device is connected, so count it as a connection too.
    function isConnected(device): bool {
        return !!device && (device.connected || device.batteryAvailable);
    }

    function hasBattery(device): bool {
        return !!device && device.batteryAvailable && Number.isFinite(Number(device.battery));
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }

    readonly property var firstActiveDevice: (root.devices ?? []).find(device => root.isConnected(device)) ?? null
    readonly property int activeDeviceCount: (root.devices ?? []).filter(device => root.isConnected(device)).length
    readonly property bool connected: (root.devices ?? []).some(d => root.isConnected(d))

    property list<var> connectedDevices: (root.devices ?? []).filter(d => root.isConnected(d)).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: (root.devices ?? []).filter(d => d.paired && !root.isConnected(d)).sort(sortFunction)
    property list<var> unpairedDevices: (root.devices ?? []).filter(d => !d.paired && !root.isConnected(d)).sort(sortFunction)
    readonly property list<var> connectedBatteryDevices: connectedDevices.filter(device => root.hasBattery(device))
    readonly property var primaryConnectedDevice: firstActiveDevice ?? connectedDevices[0] ?? null
    readonly property var primaryBatteryDevice: root.hasBattery(primaryConnectedDevice)
        ? primaryConnectedDevice
        : connectedBatteryDevices[0] ?? null
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]

    // Keep one object per address across polls so ListView delegates keep
    // their identity and don't reset when a field changes.
    function shapeDevice(data) {
        const cached = root.deviceCache[data.address];
        const device = cached ?? {};
        device.address = data.address;
        device.name = data.name ?? "";
        device.icon = data.icon ?? "";
        device.paired = data.paired === true;
        device.connected = data.connected === true;
        device.battery = data.battery ?? 0;
        device.batteryAvailable = data.batteryAvailable === true;
        if (!cached) {
            device.connect = () => root.runAction("connect", device.address);
            device.disconnect = () => root.runAction("disconnect", device.address);
            device.pair = () => root.runAction("pair", device.address);
            device.forget = () => root.runAction("forget", device.address);
        }
        root.deviceCache[data.address] = device;
        return device;
    }

    function stateSignature(state) {
        if (!state) return "";
        const parts = [state.available, state.enabled, state.discovering];
        for (const d of (state.devices ?? [])) {
            parts.push(d.address, d.name, d.icon, d.paired, d.connected, d.battery, d.batteryAvailable);
        }
        return parts.join("|");
    }

    // exec() stops any currently running process, so two actions issued in
    // the same handler must become ONE helper invocation: the helper accepts
    // several flags at once and re-emits fresh state after running them.
    function runActions(actions) {
        const args = [];
        for (const [action, value] of actions) {
            switch (action) {
            case "power":    args.push("--power", value === "on" ? "on" : "off"); break;
            case "discover": args.push("--discover", value === "start" ? "start" : "stop"); break;
            case "connect":
            case "disconnect":
            case "pair":
            case "forget":   args.push("--" + action, value); break;
            default: break;
            }
        }
        if (args.length > 0)
            stateProc.exec(["python3", "-I", root.helperScript, ...args]);
    }

    function runAction(action, address) {
        root.runActions([[action, address]]);
    }

    function setPower(on: bool) {
        if (root.quickshellLive) {
            const adapter = Bluetooth.defaultAdapter;
            if (adapter) adapter.enabled = on;
            return;
        }
        root.runActions([["power", on ? "on" : "off"]]);
    }

    function startDiscovery() {
        if (root.quickshellLive) {
            const adapter = Bluetooth.defaultAdapter;
            if (adapter) adapter.discovering = true;
            return;
        }
        root.runActions([["discover", "start"]]);
    }

    function stopDiscovery() {
        if (root.quickshellLive) {
            const adapter = Bluetooth.defaultAdapter;
            if (adapter) adapter.discovering = false;
            return;
        }
        root.runActions([["discover", "stop"]]);
    }

    function setPowerAndDiscover(on: bool) {
        if (root.quickshellLive) {
            const adapter = Bluetooth.defaultAdapter;
            if (adapter) {
                adapter.enabled = on;
                adapter.discovering = on;
            }
            return;
        }
        root.runActions([
            ["power", on ? "on" : "off"],
            ["discover", on ? "start" : "stop"]
        ]);
    }

    function togglePower() {
        root.setPower(!root.enabled);
    }

    Process {
        id: stateProc
        command: ["python3", "-I", root.helperScript]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const parsed = JSON.parse(line);
                    root.helperRan = true;
                    const sig = root.stateSignature(parsed);
                    if (sig === root.fallbackSignature) return;
                    root.fallbackSignature = sig;
                    root.fallbackState = parsed;
                    root.shapedFallbackDevices = (parsed.devices ?? []).map(d => root.shapeDevice(d));
                } catch (e) {
                    // Malformed/partial line: ignore; the next poll fixes it.
                }
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 5000
        repeat: true
        running: !root.quickshellLive
        onTriggered: {
            if (!stateProc.running) stateProc.exec(["python3", "-I", root.helperScript]);
        }
    }

    Component.onCompleted: {
        if (!root.quickshellLive) stateProc.exec(["python3", "-I", root.helperScript]);
    }
}
