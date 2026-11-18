#!/usr/bin/env bash
# Remove the user-level end4-pC Cast helper.
#
# Run as the desktop user, not root.  A running cast session is stopped first.
# Configuration (config.json, sinks.json, session.json, cast.log) is kept unless
# --purge is passed.  No /etc or system files are ever touched by this script.
#
# Usage:
#   ./optional/cast/uninstall-user.sh          # remove helper, keep config
#   ./optional/cast/uninstall-user.sh --purge  # also remove config + build dir
#
set -euo pipefail

HELPER="${HOME}/.local/bin/end4pc-cast"
CONFIG_ROOT="${XDG_CONFIG_HOME:-${HOME}/.config}"
CONFIG_DIR="${CONFIG_ROOT}/end4-pC/cast"
DATA_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}"
BUILD_DIR="${DATA_ROOT}/end4pc-cast"

if [ "${EUID}" -eq 0 ]; then
    echo "Run this as the desktop user (not root)." >&2
    exit 1
fi

if [ -x "$HELPER" ]; then
    "$HELPER" stop >/dev/null 2>&1 || true
    rm -f "$HELPER"
    echo "Stopped any cast session and removed: $HELPER"
else
    echo "No installed helper found at $HELPER (nothing to remove)."
fi

if [ "${1:-}" = "--purge" ]; then
    rm -rf "$CONFIG_DIR" "$BUILD_DIR"
    echo "Purged: $CONFIG_DIR and $BUILD_DIR"
else
    echo "Kept config: $CONFIG_DIR (pass --purge to remove it)"
fi

echo "Cast helper uninstalled. Manual /etc changes (wpa_supplicant, ufw 7236/tcp) are left untouched."
