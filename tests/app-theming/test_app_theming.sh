#!/usr/bin/env bash
#
# Shell test for scripts/theming/app-theming.sh.
#
# Runs the script against a throwaway $HOME with a fixed palette so the
# generated CSS is deterministic. No real gsettings / dbus / plasma calls are
# made (APP_THEMING_NO_EXTERNAL=1), but every file write is exercised.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_THEMING="$REPO_ROOT/scripts/theming/app-theming.sh"
FEATURE_DIR="$REPO_ROOT/features/app-theming"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
export APP_THEMING_NO_EXTERNAL=1

mkdir -p "$XDG_CONFIG_HOME/illogical-impulse" \
         "$XDG_CONFIG_HOME/gtk-3.0" \
         "$XDG_CONFIG_HOME/gtk-4.0" \
         "$XDG_CONFIG_HOME/gtk-2.0" \
         "$XDG_CONFIG_HOME/hypr/hyprland" \
         "$XDG_STATE_HOME/quickshell/user/generated" \
         "$XDG_DATA_HOME/themes/adw-gtk3" \
         "$XDG_DATA_HOME/themes/adw-gtk3-dark" \
         "$XDG_DATA_HOME/Kvantum/MaterialAdw"
printf '# MaterialAdw\n' \
    > "$XDG_DATA_HOME/Kvantum/MaterialAdw/MaterialAdw.kvconfig"
# Isolate detection from the host's real theme directories.
export APP_THEMING_THEME_ROOTS="$XDG_DATA_HOME/themes"
export APP_THEMING_KVANTUM_ROOTS="$XDG_DATA_HOME/Kvantum"
printf 'hl.env("QT_STYLE_OVERRIDE", "kvantum")\n' \
    > "$XDG_CONFIG_HOME/hypr/hyprland/env.lua"

cat > "$XDG_STATE_HOME/quickshell/user/generated/material_colors.scss" <<'SCSS'
$darkmode: true;
$primary: #ff0000;
$onPrimary: #ffffff;
$surface: #101010;
$onSurface: #eeeeee;
$surfaceContainer: #202020;
$outline: #808080;
$error: #ff1111;
SCSS
PALETTE="$XDG_STATE_HOME/quickshell/user/generated/material_colors.scss"

printf '{}\n' > "$SHELL_CONFIG_FILE"

pass=0
fail=0

check() {
    local name="$1" condition="$2"
    if eval "$condition"; then
        printf 'PASS %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$name"
        fail=$((fail + 1))
    fi
}

# --- existing user content + window decoration setting must survive --------
cat > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" <<'INI'
[Settings]
gtk-decoration-layout=:
gtk-theme-name=some-old-theme
gtk-application-prefer-dark-theme=false
gtk-font-name=Sans 11
INI

printf '/* my own gtk css */\n.window { padding: 4px; }\n' \
    > "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
printf 'gtk-theme-name="some-old-theme"\n' > "$XDG_CONFIG_HOME/gtk-2.0/gtkrc"

# --- light mode ------------------------------------------------------------
# The palette's $darkmode tracks the mode (matugen regenerates it per switch).
sed -i 's/^\$darkmode:.*/\$darkmode: false;/' "$PALETTE"
bash "$APP_THEMING" light
LIGHT_CSS="$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
check 'light: primary colour rendered' \
    "grep -q '#ff0000' '$LIGHT_CSS'"
check 'light: darkmode placeholder is false' \
    "grep -q 'mode: false' '$LIGHT_CSS'"
check 'light: guard markers present' \
    "grep -qF '/* end4-pC MD3 app theming:begin */' '$LIGHT_CSS' && grep -qF '/* end4-pC MD3 app theming:end */' '$LIGHT_CSS'"
check 'light: user CSS preserved' \
    "grep -qF '.window { padding: 4px; }' '$LIGHT_CSS'"
check 'light: gtk-decoration-layout preserved' \
    "grep -q '^gtk-decoration-layout=:$' '$XDG_CONFIG_HOME/gtk-3.0/settings.ini'"
check 'light: gtk-theme-name switched' \
    "grep -q '^gtk-theme-name=adw-gtk3$' '$XDG_CONFIG_HOME/gtk-3.0/settings.ini'"
check 'light: unrelated ini key preserved' \
    "grep -q '^gtk-font-name=Sans 11$' '$XDG_CONFIG_HOME/gtk-3.0/settings.ini'"
check 'light: gtkrc written' \
    "test -f '$XDG_CONFIG_HOME/gtk-2.0/gtkrc' || grep -q 'adw-gtk3' '$XDG_CONFIG_HOME/gtk-2.0/gtkrc' 2>/dev/null"
check 'light: gtk4 css rendered' \
    "grep -q '#101010' '$XDG_CONFIG_HOME/gtk-4.0/gtk.css'"
check 'light: kde colour scheme set' \
    "grep -q '^ColorScheme=Matugen$' '$XDG_CONFIG_HOME/kdeglobals'"
check 'light: kvantum theme driven by app-theming' \
    "grep -q '^theme=MaterialAdw$' '$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig'"
check 'light: qt6ct colour scheme set' \
    "grep -q '^color_scheme=matugen$' '$XDG_CONFIG_HOME/qt6ct/qt6ct.conf'"
check 'thunar: toolbar border and shadow removed' \
    "grep -qF '.thunar toolbar,' '$LIGHT_CSS' && grep -qF 'border: none;' '$LIGHT_CSS' && grep -qF 'box-shadow: none;' '$LIGHT_CSS'"
check 'thunar: path bar border removed' \
    "grep -qF '.thunar .path-bar,' '$LIGHT_CSS'"
check 'thunar: linked entries borderless with shell radius' \
    "grep -qF '.thunar .linked entry {' '$LIGHT_CSS' && grep -qF 'border-radius: 8px;' '$LIGHT_CSS'"
check 'thunar: toolbar radius uses shell token literal' \
    "grep -qF 'border-radius: 12px;' '$LIGHT_CSS'"
check 'thunar: every rule sits inside the guard markers' \
    "awk '/end4-pC MD3 app theming:begin/{in_guard=1; next} /end4-pC MD3 app theming:end/{in_guard=0} in_guard && /\\.thunar toolbar,/{found=1} END{exit !found}' '$LIGHT_CSS' && ! awk '/end4-pC MD3 app theming:begin/{in_guard=1; next} /end4-pC MD3 app theming:end/{in_guard=0} !in_guard && /\\.thunar toolbar,/{found=1} END{exit !found}' '$LIGHT_CSS'"

# --- idempotency -----------------------------------------------------------
cp "$LIGHT_CSS" "$TMP_DIR/light-1.css"
bash "$APP_THEMING" light
check 'idempotent: second light apply is byte-identical' \
    "cmp -s '$TMP_DIR/light-1.css' '$LIGHT_CSS'"

# --- dark mode replaces the block, not the file ----------------------------
sed -i 's/^\$darkmode:.*/\$darkmode: true;/' "$PALETTE"
bash "$APP_THEMING" dark
check 'dark: darkmode placeholder is true' \
    "grep -q 'mode: true' '$LIGHT_CSS'"
check 'dark: user CSS still preserved' \
    "grep -qF '.window { padding: 4px; }' '$LIGHT_CSS'"
check 'dark: only one guarded block' \
    "test \"\$(grep -cF '/* end4-pC MD3 app theming:begin */' '$LIGHT_CSS')\" = 1"
check 'dark: gtk-theme-name switched' \
    "grep -q '^gtk-theme-name=adw-gtk3-dark$' '$XDG_CONFIG_HOME/gtk-3.0/settings.ini'"
check 'dark: kde colour scheme set' \
    "grep -q '^ColorScheme=Matugen$' '$XDG_CONFIG_HOME/kdeglobals'"

# --- Qt Quick / Kirigami sink -----------------------------------------------
QQC_CONF="$XDG_CONFIG_HOME/qtquickcontrols2.conf"
ENV_LUA="$XDG_CONFIG_HOME/hypr/hyprland/env.lua"
check 'qtquick: conf has dark Material theme' \
    "grep -q '^Theme=Dark$' '$QQC_CONF'"
check 'qtquick: conf has matugen accent' \
    "grep -q '^Accent=#ff0000$' '$QQC_CONF'"
check 'qtquick: conf path exported to apps' \
    "grep -qF 'hl.env(\"QT_QUICK_CONTROLS_CONF\", \"$QQC_CONF\")' '$ENV_LUA'"
check 'qtquick: style exported to apps' \
    "grep -qF 'hl.env(\"QT_QUICK_CONTROLS_STYLE\", \"Material\")' '$ENV_LUA'"
check 'qtquick: material theme exported to apps' \
    "grep -qF 'hl.env(\"QT_QUICK_CONTROLS_MATERIAL_THEME\", \"Dark\")' '$ENV_LUA'"
check 'qtquick: Qt platform theme exported for Fusion fallback' \
    "grep -qF 'hl.env(\"QT_QPA_PLATFORMTHEME\", \"qt6ct\")' '$ENV_LUA'"
check 'qtquick: conflicting QT_STYLE_OVERRIDE removed from env.lua' \
    "! grep -qF 'QT_STYLE_OVERRIDE' '$ENV_LUA'"
cp "$QQC_CONF" "$TMP_DIR/qqc-1.conf"
cp "$LIGHT_CSS" "$TMP_DIR/dark-1.css"
bash "$APP_THEMING" dark
check 'qtquick: repeated apply is byte-identical' \
    "cmp -s '$TMP_DIR/qqc-1.conf' '$QQC_CONF'"
check 'dark: guarded CSS byte-identical on second apply' \
    "cmp -s '$TMP_DIR/dark-1.css' '$LIGHT_CSS'"

# --- resolved map drives GTK + Kvantum names --------------------------------
printf '{"appearance":{"appTheming":{"provision":false}}}\n' > "$SHELL_CONFIG_FILE"
mkdir -p "$XDG_STATE_HOME/quickshell/theme-stack"
printf '{"gtkTheme":"MyFamily-dark","kvantumTheme":"CustomKv","mode":"dark"}\n' \
    > "$XDG_STATE_HOME/quickshell/theme-stack/resolved.json"
bash "$APP_THEMING" dark
check 'resolved: gtk theme name comes from resolved map' \
    "grep -q '^gtk-theme-name=MyFamily-dark$' '$XDG_CONFIG_HOME/gtk-3.0/settings.ini'"
check 'resolved: kvantum theme name comes from resolved map' \
    "grep -q '^theme=CustomKv$' '$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig'"

# --- qtQuick toggle ---------------------------------------------------------
printf '{"appearance":{"appTheming":{"provision":false,"qtQuick":false}}}\n' \
    > "$SHELL_CONFIG_FILE"
rm -f "$QQC_CONF"
bash "$APP_THEMING" dark
check 'qtQuick=false: no conf file is written' \
    "test ! -f '$QQC_CONF'"

# --- refresh mode ----------------------------------------------------------
printf '[Settings]\ngtk-theme-name=adw-gtk3-dark\n' \
    > "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
printf '/* user gtk4 css */\n' > "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"
bash "$APP_THEMING" --refresh
check 'refresh: gtk4 css block generated' \
    "grep -qF '/* end4-pC MD3 app theming:begin */' '$XDG_CONFIG_HOME/gtk-4.0/gtk.css'"
check 'refresh: gtk4 user css preserved' \
    "grep -qF '/* user gtk4 css */' '$XDG_CONFIG_HOME/gtk-4.0/gtk.css'"
check 'refresh: does not touch settings.ini' \
    "! grep -q 'gtk-application-prefer-dark-theme' '$XDG_CONFIG_HOME/gtk-4.0/settings.ini'"

# --- master toggle ---------------------------------------------------------
printf '{"appearance":{"appTheming":{"enable":false}}}\n' > "$SHELL_CONFIG_FILE"
cp "$LIGHT_CSS" "$TMP_DIR/before-disabled.css"
bash "$APP_THEMING" light
check 'master toggle: disabled leaves files untouched' \
    "cmp -s '$TMP_DIR/before-disabled.css' '$LIGHT_CSS'"

# --- environment.d drop-in for native KDE Connect (systemd children) --------
DROPIN="$XDG_CONFIG_HOME/environment.d/90-end4-pc-app-theming.conf"
printf '{}\n' > "$SHELL_CONFIG_FILE"
bash "$APP_THEMING" dark
check 'drop-in: dark mode sets Material Dark' \
    "grep -qx 'QT_QUICK_CONTROLS_MATERIAL_THEME=Dark' '$DROPIN'"
check 'drop-in: exposes QT_QPA_PLATFORMTHEME' \
    "grep -qx 'QT_QPA_PLATFORMTHEME=qt6ct' '$DROPIN'"
check 'drop-in: points QT_QUICK_CONTROLS_CONF at generated conf' \
    "grep -qx 'QT_QUICK_CONTROLS_CONF=$QQC_CONF' '$DROPIN'"

bash "$APP_THEMING" light
check 'drop-in: light mode rewrites to Light' \
    "grep -qx 'QT_QUICK_CONTROLS_MATERIAL_THEME=Light' '$DROPIN'"
check 'drop-in: mode switch does not duplicate keys' \
    "test \"\$(grep -c '^QT_QUICK_CONTROLS_MATERIAL_THEME=' '$DROPIN')\" -eq 1"
check 'env.lua: two applies leave no duplicate keys' \
    "test \"\$(grep -c 'hl.env(\"QT_QUICK_CONTROLS_CONF\"' '$XDG_CONFIG_HOME/hypr/hyprland/env.lua')\" -eq 1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
