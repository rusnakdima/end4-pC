#!/bin/bash
# Launch an Android app through the user's Waydroid session (no sudo).
# Usage: waydroid-app-launcher.sh <package/activity> [args...]

PKG_ACTIVITY="$1"
shift

# Ensure the session/container are up before touching the platform service.
helper=$(command -v waydroid-user-start 2>/dev/null || true)
if [ -z "$helper" ] || [ ! -x "$helper" ]; then
    helper="$HOME/.local/bin/waydroid-user-start"
fi
if [ ! -x "$helper" ]; then
    helper="$(cd "$(dirname "$0")" && pwd)/waydroid-user-start"
fi
if [ -x "$helper" ]; then
    "$helper" || exit 1
fi

exec waydroid app launch "$PKG_ACTIVITY" "$@"
