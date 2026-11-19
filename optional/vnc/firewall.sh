#!/usr/bin/env bash
# Allow the VNC port on loopback, Ethernet/Wi-Fi and Tailscale via UFW.
# Run as root: sudo end4pc-vnc-firewall [port]
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0 [port]" >&2
    exit 1
fi

port="${1:-5901}"
command -v ufw >/dev/null 2>&1 || { echo "ufw is not installed" >&2; exit 1; }

ufw allow in on lo to any port "$port" proto tcp comment "end4pc-vnc localhost"
ufw allow in on tailscale0 to any port "$port" proto tcp comment "end4pc-vnc tailscale"

# Physical Ethernet and Wi-Fi interfaces only; skip docker/virbr/ap hotspots.
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth|wl|wlan)'); do
    ufw allow in on "$iface" to any port "$port" proto tcp comment "end4pc-vnc $iface"
done

ufw status verbose
