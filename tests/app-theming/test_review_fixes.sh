#!/usr/bin/env bash
#
# Regressions for the final whole-branch review of the compatible theme stack.
# Covers env delivery to D-Bus/KDE Connect, installer opt-out, theme-family
# pinning, scheme-name drift and settings labels that overpromise installs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_THEMING="$REPO_ROOT/scripts/theming/app-theming.sh"
PROVISION="$REPO_ROOT/scripts/theming/theme-provision.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="$TMP_DIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
export CAPTURE="$TMP_DIR/capture"

mkdir -p "$XDG_CONFIG_HOME/illogical-impulse" \
         "$XDG_CONFIG_HOME/gtk-3.0" \
         "$XDG_CONFIG_HOME/hypr/hyprland" \
         "$XDG_STATE_HOME/quickshell/user/generated" \
         "$XDG_DATA_HOME/themes/adw-gtk3" \
         "$XDG_DATA_HOME/themes/adw-gtk3-dark" \
         "$XDG_DATA_HOME/themes/OtherFamily" \
         "$XDG_DATA_HOME/Kvantum/Colloid" \
         "$XDG_DATA_HOME/Kvantum/MaterialAdw" \
         "$TMP_DIR/bin" "$CAPTURE" "$TMP_DIR/base"
printf '[Settings]\ngtk-theme-name=OtherFamily\n' > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
printf '# Colloid\n' > "$XDG_DATA_HOME/Kvantum/Colloid/Colloid.kvconfig"
printf '# Colloid dark\n' > "$XDG_DATA_HOME/Kvantum/Colloid/ColloidDark.kvconfig"
printf '# MaterialAdw\n' > "$XDG_DATA_HOME/Kvantum/MaterialAdw/MaterialAdw.kvconfig"
printf '{}\n' > "$SHELL_CONFIG_FILE"
cat > "$XDG_STATE_HOME/quickshell/user/generated/material_colors.scss" <<'SCSS'
$darkmode: true;
$primary: #00ff00;
SCSS

export APP_THEMING_THEME_ROOTS="$XDG_DATA_HOME/themes"
export APP_THEMING_KVANTUM_ROOTS="$XDG_DATA_HOME/Kvantum"
# Skip materialQT.sh / the provisioner; file writes and signals still run.
export APP_THEMING_SCRIPT_DIR="$TMP_DIR/base"
export APP_THEMING_FEATURE_DIR="$REPO_ROOT/features/app-theming"

for cmd in systemctl dbus-update-activation-environment dbus-send pkill gsettings plasma-apply-colorscheme; do
    cat > "$TMP_DIR/bin/$cmd" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CAPTURE/$(basename "$0")"
exit 0
EOF
    chmod +x "$TMP_DIR/bin/$cmd"
done
cat > "$TMP_DIR/bin/pacman" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMP_DIR/bin/pacman"
export PATH="$TMP_DIR/bin:$PATH"

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

# --- C1/I5/I6: signal_apps pushes explicit values into systemd + D-Bus --------
QQC="$XDG_CONFIG_HOME/qtquickcontrols2.conf"
: > "$CAPTURE/systemctl"
: > "$CAPTURE/dbus-update-activation-environment"
: > "$CAPTURE/pkill"
APP_THEMING_NO_EXTERNAL=0 bash "$APP_THEMING" dark
check 'systemd receives the four Qt Quick variables with values' \
    "grep -qx -- '--user set-environment QT_QPA_PLATFORMTHEME=qt6ct QT_QUICK_CONTROLS_STYLE=Material QT_QUICK_CONTROLS_CONF=$QQC QT_QUICK_CONTROLS_MATERIAL_THEME=Dark' '$CAPTURE/systemctl'"
check 'D-Bus activation environment gets the same variables' \
    "grep -qx -- '--systemd QT_QPA_PLATFORMTHEME=qt6ct QT_QUICK_CONTROLS_STYLE=Material QT_QUICK_CONTROLS_CONF=$QQC QT_QUICK_CONTROLS_MATERIAL_THEME=Dark' '$CAPTURE/dbus-update-activation-environment'"
check 'KDE Connect processes are restarted on a mode apply' \
    "grep -qx -- '-TERM -x kdeconnect-app' '$CAPTURE/pkill' && grep -qx -- '-TERM -x kdeconnectd' '$CAPTURE/pkill'"

# --- I2: --refresh regenerates palette-derived config but never kills apps ----
sed -i 's/^\$primary:.*/\$primary: #ff00ff;/' \
    "$XDG_STATE_HOME/quickshell/user/generated/material_colors.scss"
: > "$CAPTURE/systemctl"
: > "$CAPTURE/dbus-update-activation-environment"
: > "$CAPTURE/pkill"
APP_THEMING_NO_EXTERNAL=0 bash "$APP_THEMING" dark --refresh
check 'refresh updates the palette-derived QQC2 accent' \
    "grep -qx 'Accent=#ff00ff' '$QQC'"
check 'refresh does not push environment or restart KDE Connect' \
    "test ! -s '$CAPTURE/systemctl' && test ! -s '$CAPTURE/dbus-update-activation-environment' && test ! -s '$CAPTURE/pkill'"
check 'refresh still sends the KDE palette-change signal' \
    "grep -q -- '--session --type=signal /KGlobalSettings' '$CAPTURE/dbus-send'"

# --- C2: --no-theme-packages really removes packages -------------------------
out="$(APP_THEME_PACKAGES=0 bash "$REPO_ROOT/install-system.sh" --dry-run 2>&1)"
check 'opt-out removes official theme packages' \
    "! grep -Eq 'adw-gtk-theme|kvantum|qt6ct' <<< \"$out\""
check 'opt-out removes the Colloid AUR theme' \
    "! grep -qF 'plasma6-themes-colloid-git' <<< \"$out\""
out="$(APP_THEME_PACKAGES=1 bash "$REPO_ROOT/install-system.sh" --dry-run 2>&1)"
check 'default still installs the theme packages' \
    "grep -qF 'adw-gtk-theme' <<< \"$out\" && grep -qF 'plasma6-themes-colloid-git' <<< \"$out\""

# --- I1: preferredFamily pins the detected family -----------------------------
# Earlier applies rewrote settings.ini; restore a deliberate user selection.
printf '[Settings]\ngtk-theme-name=OtherFamily\n' > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
out="$TMP_DIR/pin-adw.json"
APP_THEMING_PREFERRED_FAMILY=adw-gtk3 APP_THEMING_RESOLVED_FILE="$out" \
    bash "$PROVISION" dark --detect
check 'adw-gtk3 pin overrides a deliberately chosen GTK family' \
    "test \"\$(jq -r .gtkTheme '$out')\" = adw-gtk3-dark"
out="$TMP_DIR/pin-colloid.json"
APP_THEMING_PREFERRED_FAMILY=Colloid APP_THEMING_RESOLVED_FILE="$out" \
    bash "$PROVISION" dark --detect
check 'Colloid pin selects the Colloid Kvantum source' \
    "test \"\$(jq -r .kvantumSourceDir '$out')\" = Colloid"

# --- I3/I4: scheme drift and settings labels ---------------------------------
check 'switchwall.sh no longer writes stale MaterialYou schemes' \
    "! grep -q 'MaterialYou' '$REPO_ROOT/scripts/colors/switchwall.sh'"
check 'settings action does not promise package installation' \
    "! grep -q -- '--install --refresh' '$REPO_ROOT/modules/ii/settings/DashboardSettingsCatalog.qml'"
check 'settings toggle is labelled as detection, not installation' \
    "! grep -qF 'Auto-install themes' '$REPO_ROOT/modules/ii/settings/DashboardSettingsCatalog.qml'"
check 'installer log does not claim packages were provisioned' \
    "! grep -qF 'Provisioning compatible app themes' '$REPO_ROOT/install.sh'"

# --- live regressions: generated destination must never be a source ----------
mkdir -p "$XDG_CONFIG_HOME/Kvantum"
printf '[General]\ntheme=MaterialAdw\n' > "$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig"
out="$TMP_DIR/generated-source.json"
APP_THEMING_RESOLVED_FILE="$out" bash "$PROVISION" dark --detect
check 'generated MaterialAdw is never selected as the Kvantum source' \
    "test \"\$(jq -r .kvantumSourceDir '$out')\" = Colloid"
check 'generated source keeps the real Colloid dark kvconfig' \
    "test \"\$(jq -r .kvantumDarkSource '$out')\" = ColloidDark.kvconfig"

# --- live regressions: broken qt6ct symlink must not abort app theming --------
rm -rf "$XDG_CONFIG_HOME/qt6ct"
ln -s "$TMP_DIR/missing-qt6ct" "$XDG_CONFIG_HOME/qt6ct"
err="$TMP_DIR/stderr"
APP_THEMING_NO_EXTERNAL=1 bash "$APP_THEMING" dark 2>"$err" >/dev/null
check 'broken qt6ct symlink is skipped with a clear warning' \
    "grep -qF 'broken symlink' '$err' && ! grep -q 'cannot create directory' '$err'"
check 'other app settings are still written with a broken qt6ct symlink' \
    "grep -q '^ColorScheme=Matugen' '$XDG_CONFIG_HOME/kdeglobals'"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
