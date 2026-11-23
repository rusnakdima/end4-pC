#!/usr/bin/env bash
# Wait briefly for org.bluez to appear on the system bus before Quickshell
# starts. Quickshell's BlueZ integration connects to the bus exactly once at
# process start; if bluetoothd is not ready yet, Bluetooth stays dead for the
# whole shell session (quickshell#1201).
#
# Always exits 0: a machine with no Bluetooth hardware still boots normally,
# and the QML fallback in BluetoothStatus covers that case.
set -u

max="${END4PC_BT_WAIT_SECONDS:-10}"
interval=0.2

busctl_probe() {
    # A hung daemon must not outlive one polling interval; otherwise N hung
    # probes could stretch the gate far past its total deadline.
    timeout "$interval" dbus-send --system \
        --dest=org.freedesktop.DBus \
        --type=method_call \
        --print-reply \
        /org/freedesktop/DBus \
        org.freedesktop.DBus.GetNameOwner \
        string:org.bluez >/dev/null 2>&1
}

elapsed=0
while :; do
    if busctl_probe; then
        exit 0
    fi
    elapsed="$(awk -v a="$elapsed" -v b="$interval" 'BEGIN { print a + b }')"
    awk -v e="$elapsed" -v m="$max" 'BEGIN { exit !(e >= m) }' && exit 0
    sleep "$interval"
done
