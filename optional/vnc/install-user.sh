#!/usr/bin/env bash
# Install the user-level end4-pC VNC controller and user service.
#
# Run as the desktop user, not root.  This script never touches /etc, VKMS,
# seatd, ACPI, display-manager or the end4-pC shell configuration.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -eq 0 ]]; then
    echo "Run this as the desktop user (not root)." >&2
    exit 1
fi

for cmd in wayvnc wayvncctl openssl systemctl install; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 1
    fi
done

install -Dm755 "$here/bin/end4pc-vnc" "$HOME/.local/bin/end4pc-vnc"
install -Dm644 "$here/systemd/wayvnc.service" "$HOME/.config/systemd/user/wayvnc.service"

"$HOME/.local/bin/end4pc-vnc" init
systemctl --user daemon-reload

# The retired full/hidden setup can still hold the default wayvnc control
# socket, which makes this user service fail with "Another wayvnc process is
# already running". Warn instead of disabling someone's service silently.
if systemctl --user list-unit-files 2>/dev/null | grep -qE '^wayvnc-mirror\.service'; then
    echo "NOTE: legacy VNC units detected. If wayvnc.service fails with" >&2
    echo "  'Another wayvnc process is already running', disable them:" >&2
    echo "  systemctl --user disable --now wayvnc-mirror.service vnc-theme-hooks.service" >&2
fi

if [[ "${1:-}" == "--enable" ]]; then
    systemctl --user enable --now wayvnc.service
fi

cat <<EOF

Installed:
  $HOME/.local/bin/end4pc-vnc
  $HOME/.config/systemd/user/wayvnc.service
  $HOME/.config/end4-pC/vnc.json
  $HOME/.config/end4-pC/vnc.secret   (mode 600)
  $HOME/.config/end4-pC/vnc/         (TLS certificate + generated wayvnc config)

Open Settings → VNC to manage capture, TLS, password, input and behaviour.
The default bind is 127.0.0.1:5900; use an SSH tunnel or set a Tailscale
address in Settings.  VNC carries no audio.

Start now:
  systemctl --user start wayvnc.service

Or start at login from the VNC Settings page.
EOF
