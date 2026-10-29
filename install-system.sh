#!/usr/bin/env bash
#
# install-system.sh — sourced by install.sh, not run directly.
# Installs system packages via yay/AUR.
#
set -euo pipefail

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

    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
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

    echo "[install-system] Installing ${#to_install[@]} package(s): ${to_install[*]}"
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        pacman -S --noconfirm --needed "${to_install[@]}"
    else
        yay -S --noconfirm "${to_install[@]}"
    fi
}
