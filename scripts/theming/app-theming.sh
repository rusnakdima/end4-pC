#!/usr/bin/env bash
#
# app-theming.sh — push end4-pC's Material You palette to external GTK/Qt apps.
#
# Usage:
#   app-theming.sh <light|dark> [--refresh] [--nosignal]
#
#   <light|dark>  Explicit mode (authoritative when given by switchwall.sh).
#                 When omitted, the mode is read from gsettings color-scheme.
#   --refresh     Regenerate only the CSS blocks from the current palette.
#                 Mode is still taken from the argument / gsettings.
#   --nosignal    Do not send live-reload signals to running applications.
#
# Environment (test seams / integration):
#   SHELL_CONFIG_FILE            Config JSON to read the appearance toggles from.
#   APP_THEMING_FEATURE_DIR      Directory holding the CSS templates + manifest.
#   APP_THEMING_PALETTE_FILE     Override the generated palette SCSS path.
#   APP_THEMING_SCRIPT_DIR       Override the base dir used to locate materialQT.sh.
#   APP_THEMING_NO_EXTERNAL=1    Skip gsettings / materialQT / dbus / plasma calls.
#                                Used by the test suite; file writes still happen.
#
# The script is deliberately dependency-light: bash + coreutils + jq (already
# required by the shell). It never removes a user's CSS file; it only replaces
# the content between the guard markers, preserving everything outside them.
set -uo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

SHELL_CONFIG_FILE="${SHELL_CONFIG_FILE:-$XDG_CONFIG_HOME/illogical-impulse/config.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_DIR="${APP_THEMING_SCRIPT_DIR:-$REPO_ROOT}"
FEATURE_DIR="${APP_THEMING_FEATURE_DIR:-$BASE_DIR/features/app-theming}"
MATERIAL_QT="$BASE_DIR/scripts/kvantum/materialQT.sh"
PALETTE_FILE="${APP_THEMING_PALETTE_FILE:-$XDG_STATE_HOME/quickshell/user/generated/material_colors.scss}"
PALETTE_FALLBACK="$XDG_CACHE_HOME/quickshell/user/generated/material_colors.scss"

BEGIN_MARK='/* end4-pC MD3 app theming:begin */'
END_MARK='/* end4-pC MD3 app theming:end */'

MODE=""
REFRESH=0
NOSIGNAL=0
NO_EXTERNAL="${APP_THEMING_NO_EXTERNAL:-0}"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --refresh) REFRESH=1 ;;
        --nosignal) NOSIGNAL=1 ;;
        light|dark) MODE="$arg" ;;
        *)
            echo "[app-theming] Unknown argument: $arg" >&2
            echo "Usage: app-theming.sh <light|dark> [--refresh] [--nosignal]" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$MODE" && "$NO_EXTERNAL" != "1" ]] && command -v gsettings >/dev/null 2>&1; then
    current="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")"
    [[ "$current" == "prefer-dark" ]] && MODE="dark" || MODE="light"
fi
[[ -z "$MODE" ]] && MODE="light"

# ---------------------------------------------------------------------------
# Config + palette helpers
# ---------------------------------------------------------------------------

# cfg <jq-filter> <default> — read a toggle from the shell config.
cfg() {
    local filter="$1" default="$2" value=""
    if [[ -f "$SHELL_CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
        value="$(jq -r "$filter // empty" "$SHELL_CONFIG_FILE" 2>/dev/null)"
    fi
    if [[ -n "$value" && "$value" != "null" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$default"
    fi
}

enabled() {
    [[ "$(cfg "$1" "$2")" == "true" ]]
}

declare -A TOKENS=()

load_palette() {
    local file="$PALETTE_FILE"
    [[ -f "$file" ]] || file="$PALETTE_FALLBACK"
    [[ -f "$file" ]] || return 1

    local line name value
    while IFS= read -r line; do
        [[ "$line" =~ ^\$?[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*: ]] || continue
        name="${line%%:*}"
        name="${name#\$}"
        name="$(printf '%s' "$name" | tr -d '[:space:]')"
        value="$(printf '%s\n' "$line" | cut -d: -f2 | cut -d ' ' -f2 | cut -d ';' -f1)"
        value="${value#\#}"
        [[ -n "$value" ]] && TOKENS["$name"]="$value"
    done < "$file"
    return 0
}

render_template() {
    local template="$1" content token value
    [[ -f "$template" ]] || return 1
    content="$(cat "$template")"

    for token in primary onPrimary surface onSurface surfaceContainer outline error; do
        value="${TOKENS[$token]:-}"
        [[ -z "$value" ]] && continue
        content="${content//\{\{$token\}\}/$value}"
    done
    # The palette's own $darkmode token is authoritative (matugen writes
    # "True"/"False"); fall back to MODE when the palette has no such token.
    local dark="${TOKENS[darkmode]:-}"
    dark="$(printf '%s' "$dark" | tr '[:upper:]' '[:lower:]')"
    [[ "$dark" != "true" && "$dark" != "false" ]] && {
        [[ "$MODE" == "dark" ]] && dark="true" || dark="false"
    }
    content="${content//\{\{darkmode\}\}/$dark}"
    printf '%s\n' "$content"
}

# set_ini_key <file> <key> <value> — update one key, leave all others (notably
# gtk-decoration-layout) untouched.
set_ini_key() {
    local file="$1" key="$2" value="$3"
    [[ -f "$file" ]] || return 0
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    elif grep -q '^\[Settings\]' "$file"; then
        sed -i "/^\[Settings\]/a ${key}=${value}" "$file"
    else
        printf '[Settings]\n%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# backup_config <file> — keep one timestamp-free backup before the first edit.
# These files live outside the repo, so a user may have local changes we must
# be able to restore by hand.
backup_config() {
    local file="$1" backup="$1.app-theming-backup"
    [[ -f "$file" && ! -f "$backup" ]] && cp -p "$file" "$backup"
    return 0
}

# set_config_key <file> <section> <key> <value> — idempotent ini-style edit that
# preserves every other key (and the section layout) of the file.
set_config_key() {
    local file="$1" section="$2" key="$3" value="$4"
    mkdir -p "$(dirname "$file")"
    if [[ ! -f "$file" ]]; then
        printf '[%s]\n%s=%s\n' "$section" "$key" "$value" > "$file"
        return 0
    fi
    backup_config "$file"
    if grep -q "^[[:space:]]*${key}=" "$file"; then
        sed -i "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$file"
    elif grep -q "^\[${section}\]" "$file"; then
        sed -i "/^\[${section}\]/a ${key}=${value}" "$file"
    else
        printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$file"
    fi
}

# write_css_block <file> <template> — replace only between the guard markers.
write_css_block() {
    local path="$1" template="$2" block existing="" tmp
    [[ -f "$template" ]] || return 0
    block="$(render_template "$template")" || return 0
    [[ -n "$block" ]] || return 0

    mkdir -p "$(dirname "$path")"
    [[ -f "$path" ]] && existing="$(cat "$path")"
    tmp="$(mktemp)"

    if [[ "$existing" == *"$BEGIN_MARK"* && "$existing" == *"$END_MARK"* ]]; then
        local prefix="${existing%%"$BEGIN_MARK"*}"
        local suffix="${existing#*"$END_MARK"}"
        printf '%s' "$prefix" > "$tmp"
        printf '%s\n' "$BEGIN_MARK" >> "$tmp"
        printf '%s\n' "$block" >> "$tmp"
        printf '%s' "$END_MARK" >> "$tmp"
        printf '%s' "$suffix" >> "$tmp"
    else
        if [[ -n "$existing" ]]; then
            printf '%s\n\n' "$existing" > "$tmp"
        fi
        printf '%s\n' "$BEGIN_MARK" >> "$tmp"
        printf '%s\n' "$block" >> "$tmp"
        # No trailing newline here: the replacement branch ends the marker the
        # same way, so repeated applies are byte-identical.
        printf '%s' "$END_MARK" >> "$tmp"
    fi
    mv "$tmp" "$path"
}

# ---------------------------------------------------------------------------
# Sinks
# ---------------------------------------------------------------------------
apply_gtk() {
    enabled '.appearance.appTheming.gtk' 'true' || return 0

    local theme prefer
    if [[ "$MODE" == "dark" ]]; then
        theme="adw-gtk3-dark"; prefer="true"
    else
        theme="adw-gtk3"; prefer="false"
    fi

    # --refresh only regenerates the CSS blocks; the mode apply already wrote
    # the settings.ini / gsettings values and must not be repeated here.
    if [[ "$REFRESH" != "1" ]]; then
        if [[ "$NO_EXTERNAL" != "1" ]] && command -v gsettings >/dev/null 2>&1; then
            gsettings set org.gnome.desktop.interface color-scheme "prefer-$MODE" >/dev/null 2>&1 || true
            gsettings set org.gnome.desktop.interface gtk-theme "$theme" >/dev/null 2>&1 || true
        fi

        set_ini_key "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" gtk-theme-name "$theme"
        set_ini_key "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" gtk-application-prefer-dark-theme "$prefer"
        set_ini_key "$XDG_CONFIG_HOME/gtk-4.0/settings.ini" gtk-theme-name "$theme"
        set_ini_key "$XDG_CONFIG_HOME/gtk-4.0/settings.ini" gtk-application-prefer-dark-theme "$prefer"

        local gtkrc="$XDG_CONFIG_HOME/gtk-2.0/gtkrc"
        mkdir -p "$(dirname "$gtkrc")"
        backup_config "$gtkrc"
        if grep -q '^gtk-theme-name=' "$gtkrc" 2>/dev/null; then
            sed -i "s|^gtk-theme-name=.*|gtk-theme-name=\"$theme\"|" "$gtkrc"
        else
            printf 'gtk-theme-name="%s"\n' "$theme" >> "$gtkrc"
        fi
    fi

    # Thunar is the GTK3 reference app; its toggle gates the MD3 CSS block.
    if enabled '.appearance.appTheming.perApp.thunar' 'true'; then
        write_css_block "$XDG_CONFIG_HOME/gtk-3.0/gtk.css" "$FEATURE_DIR/gtk3.css.tmpl"
    fi
    write_css_block "$XDG_CONFIG_HOME/gtk-4.0/gtk.css" "$FEATURE_DIR/gtk4.css.tmpl"
}

apply_qt() {
    enabled '.appearance.appTheming.qt' 'true' || return 0

    # Three independent knobs must agree before a Qt app follows light/dark:
    #   1. Kvantum's *active* theme must be the one materialQT.sh drives;
    #   2. qt6ct must hand Qt the generated matugen palette;
    #   3. the KDE ColorScheme name must be a scheme that actually exists.
    if enabled '.appearance.appTheming.manageQtStyle' 'true'; then
        set_config_key "$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig" General theme MaterialAdw
        set_config_key "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" Appearance color_scheme matugen
    fi

    # ~/.local/share/color-schemes/Matugen.colors is generated by matugen on
    # every apply, so it always matches the current mode and palette.
    set_config_key "$XDG_CONFIG_HOME/kdeglobals" General ColorScheme Matugen

    if [[ "$NO_EXTERNAL" != "1" && -f "$MATERIAL_QT" ]]; then
        bash "$MATERIAL_QT" >/dev/null 2>&1 || true
    fi

    # Dolphin is the Qt/KDE reference app; its toggle gates the live signal.
    # palette-apply is best-effort: plasma-apply-colorscheme is optional here.
    if enabled '.appearance.appTheming.perApp.dolphin' 'true' \
        && [[ "$NO_EXTERNAL" != "1" ]] \
        && command -v plasma-apply-colorscheme >/dev/null 2>&1; then
        plasma-apply-colorscheme Matugen >/dev/null 2>&1 || true
    fi
}

signal_apps() {
    [[ "$NOSIGNAL" == "1" || "$NO_EXTERNAL" == "1" ]] && return 0
    enabled '.appearance.appTheming.refreshRunningApps' 'true' || return 0

    # KGlobalSettings change notifications: 4=PaletteChanged, 0=all apps.
    if command -v dbus-send >/dev/null 2>&1; then
        dbus-send --session --type=signal /KGlobalSettings \
            org.kde.KGlobalSettings.notifyChange int32:4 int32:0 >/dev/null 2>&1 || true
    fi
    # GTK3 picks up gsettings changes via dconf automatically; nothing to do.
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if ! enabled '.appearance.appTheming.enable' 'true'; then
    exit 0
fi

if ! load_palette; then
    echo "[app-theming] Palette not found at $PALETTE_FILE — skipping CSS rendering." >&2
fi

apply_gtk
if [[ "$REFRESH" != "1" ]]; then
    apply_qt
fi
signal_apps

exit 0
