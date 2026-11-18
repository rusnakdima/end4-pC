#!/usr/bin/env bash
# Remove the user-level end4-pC VNC controller and service.
# Configuration is kept unless --purge is passed.
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "Run this as the desktop user (not root)." >&2
    exit 1
fi

systemctl --user disable --now wayvnc.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/wayvnc.service" "$HOME/.local/bin/end4pc-vnc"
systemctl --user daemon-reload 2>/dev/null || true

if [[ "${1:-}" == "--purge" ]]; then
    rm -rf "$HOME/.config/end4-pC/vnc" \
        "$HOME/.config/end4-pC/vnc.json" \
        "$HOME/.config/end4-pC/vnc.secret" \
        "$XDG_RUNTIME_DIR/end4pc-vnc-state.json" \
        "$XDG_RUNTIME_DIR/end4pc-vnc.lock"
fi

echo "Removed the VNC user service and helper.${1:+ Configuration purged.}"
