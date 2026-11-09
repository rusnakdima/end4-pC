#!/bin/bash
# Launch Android app by package name or activity
# Usage: waydroid-app-launcher.sh <package/activity> [args...]

PKG_ACTIVITY="$1"
shift

# Ensure waydroid is running
if ! waydroid status | grep -q "RUNNING"; then
    waydroid session start &
    sleep 3
fi

# Launch the app
waydroid app launch "$PKG_ACTIVITY" "$@"