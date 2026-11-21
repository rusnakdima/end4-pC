#!/usr/bin/env bash
#
# install-user.sh — install the user-level end4-pC "Cast / Remote TV" helper.
#
# Run as the desktop user, not root.  This script never touches /etc, never
# starts/stops a cast session, and never installs packages or changes the
# end4-pC shell configuration.  Optional backends (waycast / fluxcast) are only
# detected; if they are missing the script prints how to obtain them.
#
# Usage:
#   ./optional/cast/install-user.sh                     # install / refresh (idempotent)
#   ./optional/cast/install-user.sh --check            # report readiness, change nothing
#   ./optional/cast/install-user.sh --build-waycast    # build waycast from source via cargo
#   ./optional/cast/install-user.sh --build-waycast /path/to/waycast-src
#   ./optional/cast/install-user.sh --install-backends # install waycast + fluxcast into ~/.local
#   ./optional/cast/install-user.sh --uninstall        # delegate to uninstall-user.sh
#   ./optional/cast/install-user.sh -h|--help          # this text
#
# With --build-waycast the source directory may also be supplied via
# WAYCAST_SRC=/path/to/waycast-src.  The binary is installed to
# ${XDG_DATA_HOME:-~/.local/share}/end4pc-cast/waycast/waycast.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SRC="$HERE/../../scripts/cast/end4pc-cast"
HELPER_DST="${HOME}/.local/bin/end4pc-cast"
FILES_DIR="$HERE/files"

CONFIG_ROOT="${XDG_CONFIG_HOME:-${HOME}/.config}"
CONFIG_DIR="${CONFIG_ROOT}/end4-pC/cast"
DATA_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}"
WAYCAST_BUILD_DIR="${DATA_ROOT}/end4pc-cast/waycast"
WAYCAST_SRC_DIR="${DATA_ROOT}/end4pc-cast/waycast-src"
FLUXCAST_DIR="${DATA_ROOT}/end4pc-cast/fluxcast"
FLUXCAST_VENV="${DATA_ROOT}/end4pc-cast/fluxcast-venv"

MODE="install"
BUILD_WAYCAST=0
INSTALL_BACKENDS=0
WAYCAST_SRC="${WAYCAST_SRC:-}"
FAILS=0

log()  { printf '[cast] %s\n' "$*"; }
fail() { printf '[cast] FAIL: %s\n' "$*"; FAILS=$((FAILS+1)); }
ok()   { printf '[cast] ok:   %s\n' "$*"; }
warn() { printf '[cast] warn: %s\n' "$*"; }
info() { printf '[cast]      %s\n' "$*"; }

usage() { sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check)     MODE="check"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --build-waycast)
            BUILD_WAYCAST=1; shift
            if [ $# -gt 0 ] && [ -n "${1:-}" ] && [[ "${1}" != --* ]]; then
                WAYCAST_SRC="$1"; shift
            fi
            ;;
        --install-backends) INSTALL_BACKENDS=1; shift ;;
        -h|--help)   usage ;;
        *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# shared verification (install + --check)
# ---------------------------------------------------------------------------
verify() {
    log "verifying..."
    if [ "$EUID" -eq 0 ]; then
        fail "running as root; run as the desktop user"
    else
        ok "running as desktop user ($(id -un))"
    fi

    command -v python3 >/dev/null 2>&1 && ok "python3: $(python3 --version 2>&1)" \
        || fail "python3 is required for the helper"

    [ -x "$HELPER_DST" ] && ok "helper installed: $HELPER_DST" \
        || fail "helper missing or not executable: $HELPER_DST"

    [ -d "$CONFIG_DIR" ] && ok "config dir: $CONFIG_DIR" \
        || fail "config dir missing: $CONFIG_DIR"

    [ -f "$CONFIG_DIR/config.json" ] && ok "config: $CONFIG_DIR/config.json" \
        || fail "config.json missing: $CONFIG_DIR/config.json"

    # Backends and extra tools are optional: the helper degrades gracefully.
    if command -v waycast >/dev/null 2>&1 || [ -x "$WAYCAST_BUILD_DIR/waycast" ]; then
        ok "waycast backend detected"
    else
        warn "waycast not found (local Miracast/Wi-Fi Direct mode needs it)"
    fi
    if command -v fluxcast >/dev/null 2>&1; then
        ok "fluxcast backend detected"
    else
        warn "fluxcast not found (remote DLNA/Cast mode needs it)"
    fi

    for tool in iw avahi-browse pactl ffmpeg wf-recorder gst-inspect-1.0 cargo; do
        if command -v "$tool" >/dev/null 2>&1; then ok "tool: $tool"; else info "tool absent: $tool"; fi
    done

    if [ -x "$HELPER_DST" ]; then
        local json
        json="$("$HELPER_DST" status 2>/dev/null || true)"
        if printf '%s' "$json" | grep -q '"helperVersion"'; then
            ok "helper status: valid JSON with helperVersion"
        else
            fail "helper status did not return the expected JSON"
        fi
    fi

    if [ "$FAILS" -eq 0 ]; then log "ALL CHECKS PASSED"; else log "$FAILS CHECK(S) FAILED"; fi
    [ "$FAILS" -eq 0 ]
}

# ---------------------------------------------------------------------------
# build waycast from source (optional)
# ---------------------------------------------------------------------------
do_build_waycast() {
    log "building waycast from source"
    if ! command -v cargo >/dev/null 2>&1; then
        fail "cargo not found; install Rust (rustup) or omit --build-waycast"
        return 1
    fi
    if [ -z "$WAYCAST_SRC" ]; then
        fail "no source directory given; set WAYCAST_SRC=/path/to/waycast or pass --build-waycast /path/to/waycast"
        info "expected a Rust crate containing Cargo.toml with a 'waycast' binary"
        return 1
    fi
    if [ ! -f "$WAYCAST_SRC/Cargo.toml" ]; then
        fail "no Cargo.toml in '$WAYCAST_SRC'"
        return 1
    fi
    local src
    src="$(cd "$WAYCAST_SRC" && pwd)"
    log "cargo build --release in $src"
    ( cd "$src" && cargo build --release ) || { fail "cargo build failed"; return 1; }
    local bin="$src/target/release/waycast"
    [ -x "$bin" ] || { fail "built binary not found: $bin"; return 1; }
    install -Dm755 "$bin" "$WAYCAST_BUILD_DIR/waycast"
    ok "waycast installed: $WAYCAST_BUILD_DIR/waycast"
}

# ---------------------------------------------------------------------------
# install both casting backends into user-owned directories (no sudo)
# ---------------------------------------------------------------------------
do_install_fluxcast() {
    if [ -x "$FLUXCAST_DIR/bin/fluxcast" ]; then
        ok "fluxcast already installed: $FLUXCAST_DIR/bin/fluxcast"
        return 0
    fi
    command -v python3 >/dev/null 2>&1 || { fail "python3 required for fluxcast"; return 1; }
    log "creating fluxcast virtualenv"
    python3 -m venv "$FLUXCAST_VENV" || { fail "could not create fluxcast venv"; return 1; }
    "$FLUXCAST_VENV/bin/pip" install --quiet fluxcast \
        || { fail "could not install fluxcast from PyPI"; return 1; }
    mkdir -p "$FLUXCAST_DIR/bin"
    cat > "$FLUXCAST_DIR/bin/fluxcast" <<EOF
#!/usr/bin/env bash
exec "${FLUXCAST_VENV}/bin/fluxcast" "\$@"
EOF
    chmod +x "$FLUXCAST_DIR/bin/fluxcast"
    ok "fluxcast: $FLUXCAST_DIR/bin/fluxcast"
}

do_install_waycast_source() {
    if [ -x "$WAYCAST_BUILD_DIR/waycast" ]; then
        ok "waycast already installed: $WAYCAST_BUILD_DIR/waycast"
        return 0
    fi
    command -v git >/dev/null 2>&1 || { fail "git required to fetch waycast"; return 1; }
    command -v cargo >/dev/null 2>&1 || { fail "cargo required to build waycast"; return 1; }
    if [ ! -f "$WAYCAST_SRC_DIR/Cargo.toml" ]; then
        log "cloning waycast into $WAYCAST_SRC_DIR"
        git clone --depth 1 https://github.com/alchemy/waycast.git "$WAYCAST_SRC_DIR" \
            || { fail "could not clone waycast"; return 1; }
    fi
    WAYCAST_SRC="$WAYCAST_SRC_DIR"
    do_build_waycast
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
do_install() {
    if [ "$EUID" -eq 0 ]; then
        echo "Run this as the desktop user (not root)." >&2
        exit 1
    fi

    for cmd in python3 install; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Missing required command: $cmd" >&2
            exit 1
        fi
    done
    [ -f "$HELPER_SRC" ] || { echo "helper source missing: $HELPER_SRC" >&2; exit 1; }

    log "installing Cast helper for $(id -un)"

    install -Dm755 "$HELPER_SRC" "$HELPER_DST"
    ok "helper: $HELPER_DST"

    mkdir -p "$CONFIG_DIR"
    ok "config dir: $CONFIG_DIR"

    if [ -f "$FILES_DIR/config.default.json" ] && [ ! -f "$CONFIG_DIR/config.json" ]; then
        install -m600 "$FILES_DIR/config.default.json" "$CONFIG_DIR/config.json"
        ok "default config: $CONFIG_DIR/config.json"
    elif [ -f "$CONFIG_DIR/config.json" ]; then
        info "kept existing config: $CONFIG_DIR/config.json"
    fi

    if [ -f "$FILES_DIR/p2p-supplicant.conf" ] && [ ! -f "$CONFIG_DIR/p2p-supplicant.conf" ]; then
        install -m600 "$FILES_DIR/p2p-supplicant.conf" "$CONFIG_DIR/p2p-supplicant.conf"
        ok "P2P template: $CONFIG_DIR/p2p-supplicant.conf"
    fi

    if [ "$BUILD_WAYCAST" -eq 1 ]; then
        do_build_waycast || true
    fi
    if [ "$INSTALL_BACKENDS" -eq 1 ]; then
        do_install_fluxcast || true
        do_install_waycast_source || true
    fi

    # Bring the graphical session variables into the systemd --user environment
    # so a backend launched by the helper can reach the Wayland compositor.
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP >/dev/null 2>&1 \
            && ok "imported WAYLAND_DISPLAY / XDG_CURRENT_DESKTOP into systemd --user" \
            || info "could not import Wayland env into systemd --user (no user bus?)"
    fi

    # Detect backends and print guidance instead of forcing network/sudo installs.
    if ! command -v waycast >/dev/null 2>&1 && [ ! -x "$WAYCAST_BUILD_DIR/waycast" ]; then
        warn "waycast not found. To enable local (Miracast/Wi-Fi Direct) mode:"
        info "  - run: $0 --build-waycast /path/to/waycast-src   (needs cargo + source)"
        info "  - or install waycast from your package manager / a release binary onto PATH"
    fi
    if ! command -v fluxcast >/dev/null 2>&1; then
        warn "fluxcast not found. To enable remote (DLNA/Cast) mode:"
        info "  - install fluxcast on PATH (or under ${DATA_ROOT}/end4pc-cast/fluxcast/)"
        info "  - remote discovery also benefits from 'avahi-utils' (avahi-browse)"
    fi

    cat <<EOF

------------------------------------------------------------------------------
MANUAL ROOT STEPS (printed only — NOT executed by this installer)
------------------------------------------------------------------------------
Local Miracast/Wi-Fi Direct needs a P2P-capable Wi-Fi interface. After editing
the template at:
    $CONFIG_DIR/p2p-supplicant.conf
(set your country code; keep device_type=1-0050F204-1 for LG/TV full-screen)
apply it with (replace <wifi-iface> with your device from 'iw dev'):

    sudo install -Dm600 "$CONFIG_DIR/p2p-supplicant.conf" /etc/wpa_supplicant/p2p.conf
    sudo wpa_supplicant -B -i <wifi-iface> -c /etc/wpa_supplicant/p2p.conf

Alternatively, waycast ships a privileged helper that manages P2P activation
and temporary firewall rules automatically
(https://github.com/alchemy/waycast -> contrib/networkd/install.py).

Allow the inbound Miracast RTSP port through the firewall (LOCAL mode: the TV
connects to this machine on TCP 7236, so this is required for Miracast):

    sudo ufw allow 7236/tcp comment 'end4pc cast'

Verify with:  iw dev   |   sudo ufw status numbered
------------------------------------------------------------------------------

Open Settings -> Cast to pick a network mode, discover a TV and start casting.
Helper:  $HELPER_DST status
Config:  $CONFIG_DIR/config.json
Log:     $CONFIG_DIR/cast.log
EOF

    verify
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
case "$MODE" in
    install)   do_install ;;
    check)     verify ;;
    uninstall)
        if [ -f "$HERE/uninstall-user.sh" ]; then
            exec bash "$HERE/uninstall-user.sh"
        fi
        echo "uninstall-user.sh not found" >&2
        exit 1
        ;;
esac
