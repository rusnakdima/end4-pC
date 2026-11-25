#!/usr/bin/env bash
#
# install-system.sh — installs system packages via pacman/yay.
# Normally sourced by install.sh; direct execution has its own CLI:
#   ./install-system.sh --help
#   ./install-system.sh --dry-run [--extra-pkg PKG] [--no-aur]
#
set -euo pipefail

# These stay at their defaults when this file is sourced by install.sh.
DRY_RUN=0
CLI_NO_AUR=0
EXTRA_PKGS=()

# ---------------------------------------------------------------------------
# Standalone CLI (this file is normally sourced by install.sh)
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    PROG=${0##*/}
    usage() {
        cat <<'EOF'
Usage: install-system.sh [OPTIONS]

Install the system packages end4-pC needs. Normally sourced by install.sh;
running it directly is supported for package inspection and maintenance.

Options:
  -h, --help           Show this help and exit.
  --dry-run            Print the packages that would be installed, change
                       nothing. Safe to run with no network and no root.
  --no-aur             Skip AUR packages (quickshell-git) entirely.
  --extra-pkg PKG      Also install PKG; may be repeated.
  --extra-pkg=PKG      Same, single-token form.
  --                   Stop option parsing.

Exit status:
  0  all requested packages are present (or --dry-run completed)
  1  a required package could not be installed
  2  invalid command line or option value (nothing was changed)
EOF
    }
    die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 2; }
    need_value() { [[ $# -ge 2 ]] || die "$1 needs a value"; }

    while (($#)); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --dry-run) DRY_RUN=1 ;;
            --no-aur) CLI_NO_AUR=1 ;;
            --extra-pkg=*) EXTRA_PKGS+=("${1#*=}") ;;
            --extra-pkg) need_value "$@"; EXTRA_PKGS+=("$2"); shift ;;
            --) shift; break ;;
            -*) die "unknown option: $1 (try --help)" ;;
            *) die "unexpected argument: $1 (try --help)" ;;
        esac
        shift
    done
fi

# ---------------------------------------------------------------------------
# Ensure yay is available
# ---------------------------------------------------------------------------
ensure_yay() {
    if command -v yay &>/dev/null; then
        return 0
    fi

    local _tmp="/tmp/yay-install-$$"
    mkdir -p "$_tmp"
    (
        set -e
        cd "$_tmp"
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git .
        makepkg -si --noconfirm
    )
    rm -rf "$_tmp"
}

# ---------------------------------------------------------------------------
# Install a package group via yay / pacman
# ---------------------------------------------------------------------------
install_packages() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[install-system] DRY RUN: nothing will be installed."
    fi
    # pacman packages
    local pkgs=(
        brightnessctl
        ffmpeg
        pipewire-audio
        mpvpaper
        fuzzel
        cliphist
        ydotool
        wtype
        grim
        slurp
        hyprshot
        hyprlock
        hypridle
        imagemagick
        kitty
        fish
        oh-my-posh
        neovim
        libqalculate
        papirus-icon-theme
        # hotspot (AP) feature — see scripts/hotspot/README.md
        wireless-regdb # regulatory.db; without it 5 GHz AP channels are NO-IR
        hostapd        # AP daemon (helper runs its own instance, not the unit)
        dnsmasq        # DHCP/DNS for ap0 (helper runs its own instance)
        iptables       # AIC_AP_FWD / AIC_AP_NAT chains
        python         # aic-hotspot status: client list (leases ∩ station dump)
        ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}
    )

    # AUR packages. makepkg refuses to run as root, so they are only installed
    # when the installer runs as a regular user.
    local aur_pkgs=(
        quickshell-git
    )

    # An installed quickshell already provides the same binary, so the git
    # build is only needed when quickshell is missing entirely. Rebuilding it
    # from source would additionally pull in build dependencies through
    # pacman, which needs a password and would abort the whole installer.
    if command -v quickshell &>/dev/null; then
        echo "[install-system] quickshell is already installed, skipping the git build."
        aur_pkgs=()
    fi

    [[ $CLI_NO_AUR -eq 1 ]] && aur_pkgs=()

    if [[ ${EUID:-$(id -u)} -eq 0 && $DRY_RUN -eq 0 ]]; then
        echo "[install-system] Running as root: skipping AUR package(s) ${aur_pkgs[*]} (makepkg refuses root)."
        if ! pacman -Q quickshell >/dev/null 2>&1; then
            echo "[install-system] ERROR: quickshell is not installed and the AUR build was skipped." >&2
            echo "[install-system] Install it as a normal user with: yay -S quickshell-git" >&2
            return 1
        fi
        aur_pkgs=()
    fi

    local all_pkgs=("${pkgs[@]}" "${aur_pkgs[@]}")

    local to_install=()
    for pkg in "${all_pkgs[@]}"; do
        # pacman -Qi reads the unified local database, so it detects AUR packages
        # too, and unlike yay -Qi it emits no root warning.
        if ! pacman -Qi "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        fi
    done

    if ((${#to_install[@]} == 0)); then
        echo "[install-system] All packages already installed."
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[install-system] DRY RUN: would install ${#to_install[@]} package(s): ${to_install[*]}"
        return 0
    fi

    echo "[install-system] Installing ${#to_install[@]} package(s): ${to_install[*]}"
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        pacman -S --noconfirm --needed "${to_install[@]}"
    else
        yay -S --noconfirm "${to_install[@]}"
    fi
}

# Direct execution: CLI flags were parsed at the top; sourcing stops here so
# install.sh keeps exactly its old behaviour.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    install_packages
fi
