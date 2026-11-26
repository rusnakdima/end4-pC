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
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

SHELL_CONFIG_FILE="${SHELL_CONFIG_FILE:-$XDG_CONFIG_HOME/illogical-impulse/config.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_DIR="${APP_THEMING_SCRIPT_DIR:-$REPO_ROOT}"
FEATURE_DIR="${APP_THEMING_FEATURE_DIR:-$BASE_DIR/features/app-theming}"
MATERIAL_QT="$BASE_DIR/scripts/kvantum/materialQT.sh"
PALETTE_FILE="${APP_THEMING_PALETTE_FILE:-$XDG_STATE_HOME/quickshell/user/generated/material_colors.scss}"
PALETTE_FALLBACK="$XDG_CACHE_HOME/quickshell/user/generated/material_colors.scss"
RESOLVED_FILE="${APP_THEMING_RESOLVED_FILE:-$XDG_STATE_HOME/quickshell/theme-stack/resolved.json}"

RESOLVED_GTK_THEME=""
RESOLVED_KVANTUM_THEME=""

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
        # Do NOT append `// empty`: jq's alternative operator treats an explicit
        # `false` as empty, which would turn an opt-out back into the default.
        value="$(jq -r "$filter" "$SHELL_CONFIG_FILE" 2>/dev/null)"
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

    # Qt Quick Controls uses Dark/Light rather than matugen's true/false.
    local qt_theme="Light"
    [[ "$MODE" == "dark" ]] && qt_theme="Dark"
    content="${content//\{\{qtTheme\}\}/$qt_theme}"

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
    local file="$1" section="$2" key="$3" value="$4" dir
    dir="$(dirname "$file")"
    # A user may symlink a config dir to a profile that is not mounted here.
    # Never delete the link or fail the whole apply over it.
    if [[ -L "$dir" && ! -d "$dir" ]]; then
        printf '[app-theming] WARN: %s is a broken symlink; skipping %s\n' "$dir" "$file" >&2
        return 0
    fi
    mkdir -p "$dir" || return 0
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

# load_resolved() — read the theme names resolved by theme-provision.sh. An
# absent/corrupt file is fine: every caller has a dependency-free fallback.
load_resolved() {
    RESOLVED_GTK_THEME=""
    RESOLVED_KVANTUM_THEME=""
    [[ -f "$RESOLVED_FILE" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    RESOLVED_GTK_THEME="$(jq -r '.gtkTheme // empty' "$RESOLVED_FILE" 2>/dev/null)"
    RESOLVED_KVANTUM_THEME="$(jq -r '.kvantumTheme // empty' "$RESOLVED_FILE" 2>/dev/null)"
}

# write_config_file <file> <template> — render a standalone config file (no
# guard markers; unlike CSS, the whole file is ours to own).
write_config_file() {
    local path="$1" template="$2" content
    content="$(render_template "$template")" || return 0
    [[ -n "$content" ]] || return 0
    mkdir -p "$(dirname "$path")"
    backup_config "$path"
    printf '%s\n' "$content" > "$path"
}

# set_lua_env <env.lua> <key> <value> — idempotent hl.env(...) entry that leaves
# every other Hyprland environment line untouched.
set_lua_env() {
    local file="$1" key="$2" value="$3"
    local line="hl.env(\"$key\", \"$value\")"
    mkdir -p "$(dirname "$file")"
    if [[ ! -f "$file" ]]; then
        printf '%s\n' "$line" > "$file"
        return 0
    fi
    backup_config "$file"
    local tmp
    tmp="$(mktemp)"
    awk -v line="$line" -v key="$key" '
        index($0, "hl.env(\"" key "\"") == 1 { print line; seen = 1; next }
        { print }
        END { if (!seen) print line }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

# QT_STYLE_OVERRIDE=kvantum and QT_QUICK_CONTROLS_STYLE=Material together make
# Kirigami apps such as kdeconnect-app exit immediately, so drop the legacy
# override once the Qt Quick style takes over.
remove_lua_env() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    grep -qF "hl.env(\"$key\"" "$file" || return 0
    backup_config "$file"
    local tmp
    tmp="$(mktemp)"
    awk -v key="$key" 'index($0, "hl.env(\"" key "\"") != 1' "$file" > "$tmp"
    mv "$tmp" "$file"
}

# KDE/QtWidgets apps read a KColorScheme file named by kdeglobals. Matugen does
# not generate that file, so write it from the same palette tokens we use for
# GTK — otherwise Dolphin silently falls back to Breeze Light.
write_kde_scheme() {
    local primary="${TOKENS[primary]:-3daee9}"
    local on_primary="${TOKENS[onPrimary]:-ffffff}"
    local surface="${TOKENS[surface]:-1e1e1e}"
    local background="${TOKENS[background]:-}"
    local on_surface="${TOKENS[onSurface]:-eff0f1}"
    local container="${TOKENS[surfaceContainer]:-$surface}"
    local outline="${TOKENS[outline]:-7f7f7f}"
    local error="${TOKENS[error]:-ff0000}"
    [[ -n "$background" ]] || background="$surface"

    local path="$XDG_DATA_HOME/color-schemes/Matugen.colors"
    mkdir -p "$(dirname "$path")"
    {
        printf '[ColorEffects:Disabled]\nColor=#%s\nColorAmount=0.5\nColorEffect=3\n' "$surface"
        printf 'ContrastAmount=0\nContrastEffect=0\nIntensityAmount=0\nIntensityEffect=0\n\n'
        printf '[ColorEffects:Inactive]\nChangeSelectionColor=true\nColor=#%s\n' "$surface"
        printf 'ColorAmount=0.025\nColorEffect=0\nContrastAmount=0.1\nContrastEffect=0\n'
        printf 'Enable=true\nIntensityAmount=0\nIntensityEffect=0\n\n'
        for section in 'Colors:Button' 'Colors:Complementary' 'Colors:Header' \
            'Colors:Header][Inactive' 'Colors:Tooltip' 'Colors:View' 'Colors:Window'; do
            printf '[%s]\n' "$section"
            printf 'BackgroundAlternate=#%s\nBackgroundNormal=#%s\n' "$container" "$background"
            printf 'DecorationFocus=#%s\nDecorationHover=#%s\n' "$primary" "$primary"
            printf 'ForegroundActive=#%s\nForegroundInactive=#%s\n' "$on_surface" "$outline"
            printf 'ForegroundLink=#%s\nForegroundNegative=#%s\n' "$primary" "$error"
            printf 'ForegroundNeutral=#%s\nForegroundNormal=#%s\n' "$on_surface" "$on_surface"
            printf 'ForegroundPositive=#%s\nForegroundVisited=#%s\n\n' "$primary" "$primary"
        done
        printf '[Colors:Selection]\nBackgroundAlternate=#%s\n' "$primary"
        printf 'BackgroundNormal=#%s\nDecorationFocus=#%s\nDecorationHover=#%s\n' "$primary" "$primary" "$primary"
        printf 'ForegroundActive=#%s\nForegroundInactive=#%s\n' "$on_primary" "$on_primary"
        printf 'ForegroundLink=#%s\nForegroundNegative=#%s\n' "$on_primary" "$on_primary"
        printf 'ForegroundNeutral=#%s\nForegroundNormal=#%s\n' "$on_primary" "$on_primary"
        printf 'ForegroundPositive=#%s\nForegroundVisited=#%s\n\n' "$on_primary" "$on_primary"
        printf '[General]\nColorScheme=Matugen\nName=Matugen\nshadeSortColumn=true\n\n'
        printf '[KDE]\ncontrast=4\n\n[WM]\nactiveBackground=#%s\n' "$background"
        printf 'activeBlend=252,252,252\nactiveForeground=#%s\n' "$on_surface"
        printf 'inactiveBackground=#%s\ninactiveBlend=161,169,177\n' "$background"
        printf 'inactiveForeground=#%s\n' "$outline"
    } > "$path"
}

# A broken symlink in place of a config directory (left by another theme
# package) makes every qt6ct write fail silently. Replace it with a real dir.
ensure_real_dir() {
    local dir="$1"
    if [[ -L "$dir" && ! -d "$dir" ]]; then
        echo "[app-theming] WARN: $dir is a broken symlink; replacing it with a real directory." >&2
        rm -f "$dir" || return 1
    fi
    mkdir -p "$dir"
}

# qt6ct needs an actual palette file plus [Appearance] pointers to it; writing
# `color_scheme=matugen` alone leaves QtWidgets on a light palette (white rows
# in Dolphin). QPalette roles are 21 comma-separated #AARRGGBB colors.
write_qt6ct_scheme() {
    local primary="${TOKENS[primary]:-3daee9}"
    local on_primary="${TOKENS[onPrimary]:-ffffff}"
    local surface="${TOKENS[surface]:-1e1e1e}"
    local background="${TOKENS[background]:-}"
    local on_surface="${TOKENS[onSurface]:-eff0f1}"
    local container="${TOKENS[surfaceContainer]:-$surface}"
    local outline="${TOKENS[outline]:-7f7f7f}"
    [[ -n "$background" ]] || background="$surface"

    local dir="$XDG_CONFIG_HOME/qt6ct/colors"
    ensure_real_dir "$dir" || return 0
    local path="$dir/Matugen.conf"
    local colors
    colors=$(printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s' \
        "#ff$on_surface" "#ff$container" "#ff$container" "#ff$container" \
        "#ff$background" "#ff$surface" "#ff$on_surface" "#ff$on_primary" \
        "#ff$on_surface" "#ff$background" "#ff$surface" "#ff$background" \
        "#ff$primary" "#ff$on_primary" "#ff$primary" "#ff$primary" \
        "#ff$container" "#ff$on_surface" "#ff$on_surface" "#ff$surface" "#ff$outline")
    printf '[ColorScheme]\nactive_colors=%s\ninactive_colors=%s\ndisabled_colors=%s\n' \
        "$colors" "$colors" "$colors" > "$path"
}

# ---------------------------------------------------------------------------
# Sinks
# ---------------------------------------------------------------------------
apply_gtk() {
    enabled '.appearance.appTheming.gtk' 'true' || return 0

    local theme prefer family
    family="$(cfg '.appearance.appTheming.preferredFamily' 'auto')"
    [[ "$family" == "auto" ]] && family="adw-gtk3"
    theme="${RESOLVED_GTK_THEME:-$family}"
    if [[ "$MODE" == "dark" ]]; then
        [[ "$theme" == *-dark ]] || theme="${theme}-dark"
        prefer="true"
    else
        theme="${theme%-dark}"
        prefer="false"
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
        set_config_key "$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig" General theme \
            "${RESOLVED_KVANTUM_THEME:-MaterialAdw}"
        ensure_real_dir "$XDG_CONFIG_HOME/qt6ct" || return 0
        write_qt6ct_scheme
        set_config_key "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" Appearance color_scheme_path \
            "$XDG_CONFIG_HOME/qt6ct/colors/Matugen.conf"
        set_config_key "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" Appearance custom_palette true
    fi

    # Generate the scheme ourselves from the active palette, then point
    # kdeglobals at it. Without the file, KDE apps fall back to Breeze Light.
    write_kde_scheme
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

# environment.d is read by systemd --user, so apps launched by KDE Connect's
# daemon or by user units inherit the Qt Quick mode even though they are not
# children of Hyprland. The drop-in is regenerated (not appended) per mode.
write_environment_dropin() {
    local conf="$1" theme="$2"
    local dropin="$XDG_CONFIG_HOME/environment.d/90-end4-pc-app-theming.conf"
    mkdir -p "$(dirname "$dropin")"
    {
        printf '# Generated by end4-pC app theming — do not edit by hand.\n'
        printf 'QT_QPA_PLATFORMTHEME=qt6ct\n'
        printf 'QT_QUICK_CONTROLS_STYLE=Material\n'
        printf 'QT_QUICK_CONTROLS_CONF=%s\n' "$conf"
        printf 'QT_QUICK_CONTROLS_MATERIAL_THEME=%s\n' "$theme"
    } > "$dropin"
}

# Qt Quick Controls (KDE Connect, EasyEffects, other Kirigami apps) do not read
# the QtWidgets style at all. They need their own config plus explicit env vars:
# Qt only loads qtquickcontrols2.conf from a resource or QT_QUICK_CONTROLS_CONF.
apply_qtquick() {
    enabled '.appearance.appTheming.qtQuick' 'true' || return 0

    local conf="$XDG_CONFIG_HOME/qtquickcontrols2.conf"
    local env_file="$XDG_CONFIG_HOME/hypr/hyprland/env.lua"
    local theme="Light"
    [[ "$MODE" == "dark" ]] && theme="Dark"

    write_config_file "$conf" "$FEATURE_DIR/qtquickcontrols2.conf.tmpl"
    set_lua_env "$env_file" QT_QUICK_CONTROLS_CONF "$conf"
    set_lua_env "$env_file" QT_QUICK_CONTROLS_STYLE Material
    set_lua_env "$env_file" QT_QUICK_CONTROLS_MATERIAL_THEME "$theme"
    set_lua_env "$env_file" QT_QPA_PLATFORMTHEME qt6ct
    remove_lua_env "$env_file" QT_STYLE_OVERRIDE
    write_environment_dropin "$conf" "$theme"
}

signal_apps() {
    [[ "$NOSIGNAL" == "1" || "$NO_EXTERNAL" == "1" ]] && return 0
    enabled '.appearance.appTheming.refreshRunningApps' 'true' || return 0

    # KGlobalSettings change notifications: 4=PaletteChanged, 0=all apps.
    if command -v dbus-send >/dev/null 2>&1; then
        dbus-send --session --type=signal /KGlobalSettings \
            org.kde.KGlobalSettings.notifyChange int32:4 int32:0 >/dev/null 2>&1 || true
    fi

    # Qt Quick apps (KDE Connect, EasyEffects) cache their style at startup.
    # --refresh only repaints with the new palette; the environment must not be
    # pushed and apps must not be killed on every wallpaper change.
    if [[ "$REFRESH" == "1" ]]; then
        return 0
    fi
    enabled '.appearance.appTheming.qtQuick' 'true' || return 0

    local qqc_conf="$XDG_CONFIG_HOME/qtquickcontrols2.conf"
    local qqc_theme="Light"
    [[ "$MODE" == "dark" ]] && qqc_theme="Dark"
    local -a qenv=(
        "QT_QPA_PLATFORMTHEME=qt6ct"
        "QT_QUICK_CONTROLS_STYLE=Material"
        "QT_QUICK_CONTROLS_CONF=$qqc_conf"
        "QT_QUICK_CONTROLS_MATERIAL_THEME=$qqc_theme"
    )

    # import-environment would ignore unset shell variables. Pass explicit
    # values instead; systemd --user does not re-read environment.d on change.
    # The base installer also set QT_STYLE_OVERRIDE=kvantum; that style and the
    # Qt Quick Material style make kdeconnect-app exit immediately, and a stale
    # override in systemd/D-Bus survives into every restarted app.
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user unset-environment QT_STYLE_OVERRIDE >/dev/null 2>&1 || true
        systemctl --user set-environment "${qenv[@]}" >/dev/null 2>&1 || true
    fi
    # KDE Connect's daemon is D-Bus activated, not a systemd user unit, so it
    # does not inherit the user manager's environment either. D-Bus has no
    # unset operation; an empty value is treated as "no override" by Qt.
    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment --systemd "${qenv[@]}" >/dev/null 2>&1 || true
        dbus-update-activation-environment --systemd QT_STYLE_OVERRIDE= >/dev/null 2>&1 || true
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -TERM -x kdeconnect-app >/dev/null 2>&1 || true
        pkill -TERM -x kdeconnectd >/dev/null 2>&1 || true
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

if enabled '.appearance.appTheming.provision' 'true'; then
    PROVISIONER_SCRIPT="$BASE_DIR/scripts/theming/theme-provision.sh"
    if [[ -f "$PROVISIONER_SCRIPT" ]]; then
        APP_THEMING_PREFERRED_FAMILY="$(cfg '.appearance.appTheming.preferredFamily' 'auto')"
        export APP_THEMING_PREFERRED_FAMILY
        bash "$PROVISIONER_SCRIPT" "$MODE" --detect >/dev/null 2>&1 || true
    fi
fi
load_resolved

apply_gtk
# The QQC2 Accent comes from the live palette, so a --refresh must rewrite it
# too; only the one-shot settings/style writes are skipped in refresh mode.
apply_qtquick
if [[ "$REFRESH" != "1" ]]; then
    apply_qt
fi
signal_apps

exit 0
