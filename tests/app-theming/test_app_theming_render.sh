#!/usr/bin/env bash
#
# Rendering test for the app-theming layer.
#
# The file-content test (test_app_theming.sh) proves the script writes the
# right bytes. This one proves apps actually LOOK right: it switches the real
# deploy between light and dark on Xvfb :99, launches fresh GTK and Qt apps,
# screenshots them and samples pixels. This is the gate that would have
# caught the "Dolphin stays light / stays dark in both modes" bug.
#
# Usage: test_app_theming_render.sh
#   APP_THEMING_TEST_CONFIG=<deploy dir>   default: ~/.config/quickshell/end4-pC
#
# Everything touched in $HOME is backed up and restored on exit.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_ROOT="${APP_THEMING_TEST_CONFIG:-$HOME/.config/quickshell/end4-pC}"
SWITCHWALL="$CONFIG_ROOT/scripts/colors/switchwall.sh"

if [[ ! -f "$SWITCHWALL" ]]; then
    echo "SKIP: no deployed switchwall.sh at $SWITCHWALL" >&2
    exit 0
fi
for tool in import magick xdotool; do
    command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool not installed" >&2; exit 0; }
done

# ---------------------------------------------------------------------------
# Display :99 (start it if needed)
# ---------------------------------------------------------------------------
export DISPLAY=:99
if ! xdpyinfo -display :99 >/dev/null 2>&1; then
    Xvfb :99 -screen 0 1000x800x24 >/tmp/app-theming-xvfb.log 2>&1 &
    XVFB_PID=$!
    for _ in $(seq 1 30); do
        xdpyinfo -display :99 >/dev/null 2>&1 && break
        sleep 0.3
    done
fi
if ! xdpyinfo -display :99 >/dev/null 2>&1; then
    echo "SKIP: could not start Xvfb :99" >&2
    exit 0
fi

# App env: GTK maps on X11 with the cairo renderer; Qt uses xcb + the same
# style knobs the shell installs (qt6ct + Kvantum, never Breeze).
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export GDK_BACKEND=x11 GSK_RENDERER=cairo
export QT_QPA_PLATFORM=xcb QT_QPA_PLATFORMTHEME=qt6ct QT_STYLE_OVERRIDE=kvantum

# ---------------------------------------------------------------------------
# Backup everything we touch, and sync the repo's implementation into the
# deploy so we test the code under review rather than a stale copy.
# ---------------------------------------------------------------------------
BACKUP="$(mktemp -d)"
RESULTS="$(mktemp -d)"
GS_BEFORE="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"

save_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    local dest="$BACKUP/${path#/}"
    mkdir -p "$(dirname "$dest")"
    cp -p "$path" "$dest"
}

HOME_FILES=(
    "$HOME/.config/gtk-3.0/gtk.css"
    "$HOME/.config/gtk-4.0/gtk.css"
    "$HOME/.config/gtk-3.0/settings.ini"
    "$HOME/.config/gtk-4.0/settings.ini"
    "$HOME/.config/kdeglobals"
    "$HOME/.config/Kvantum/kvantum.kvconfig"
    "$HOME/.config/Kvantum/MaterialAdw/MaterialAdw.kvconfig"
    "$HOME/.config/qt6ct/qt6ct.conf"
    "$HOME/.local/state/quickshell/user/generated/material_colors.scss"
    "$HOME/.local/share/color-schemes/Matugen.colors"
    "$HOME/.config/hypr/hyprland/env.lua"
)
for f in "${HOME_FILES[@]}"; do save_file "$f"; done
DEPLOY_FILES=(
    "$CONFIG_ROOT/scripts/theming/app-theming.sh"
    "$CONFIG_ROOT/scripts/kvantum/materialQT.sh"
)
for f in "${DEPLOY_FILES[@]}"; do save_file "$f"; done
if [[ -d "$CONFIG_ROOT/features/app-theming" ]]; then
    mkdir -p "$BACKUP/${CONFIG_ROOT#/}/features"
    cp -a "$CONFIG_ROOT/features/app-theming" "$BACKUP/${CONFIG_ROOT#/}/features/"
fi

cleanup() {
    pkill -f '^dolphin' 2>/dev/null || true
    pkill -f '^thunar' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme "$GS_BEFORE" 2>/dev/null || true
    # Restore saved files.
    while IFS= read -r -d '' saved; do
        local orig="/${saved#"$BACKUP"/}"
        mkdir -p "$(dirname "$orig")"
        cp -p "$saved" "$orig"
    done < <(find "$BACKUP" -type f -print0 2>/dev/null)
    # Restore the deploy feature dir as a whole (cp -a above).
    if [[ -d "$BACKUP/${CONFIG_ROOT#/}/features/app-theming" ]]; then
        rm -rf "$CONFIG_ROOT/features/app-theming"
        cp -a "$BACKUP/${CONFIG_ROOT#/}/features/app-theming" "$CONFIG_ROOT/features/"
    fi
    [[ -n "${XVFB_PID:-}" ]] && kill "$XVFB_PID" 2>/dev/null || true
    rm -rf "$BACKUP" "$RESULTS"
}
trap cleanup EXIT

mkdir -p "$CONFIG_ROOT/features"
cp "$REPO_ROOT/scripts/theming/app-theming.sh" "$CONFIG_ROOT/scripts/theming/app-theming.sh"
cp "$REPO_ROOT/scripts/kvantum/materialQT.sh" "$CONFIG_ROOT/scripts/kvantum/materialQT.sh"
cp -a "$REPO_ROOT/features/app-theming" "$CONFIG_ROOT/features/"

pass=0
fail=0
check() {
    local name="$1" true="$2"
    if [[ "$true" == "1" ]]; then
        printf 'PASS %s\n' "$name"; pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$name"; fail=$((fail + 1))
    fi
}

# srgb(r,g,b) -> perceived luminance 0..255
lum() {
    local px="$1" r g b
    r="$(sed -nE 's/.*\(srgb\(?([0-9]+),.*/\1/p' <<< "$px")"
    [[ -n "$r" ]] || { sed -nE 's/.*rgba?\(([0-9]+).*/\1/p' <<< "$px"; return; }
    g="$(sed -nE 's/.*\([0-9]+, *([0-9]+),.*/\1/p' <<< "$px")"
    b="$(sed -nE 's/.*\([0-9]+, *[0-9]+, *([0-9]+).*/\1/p' <<< "$px")"
    awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN { printf "%.0f", 0.2126*r + 0.7152*g + 0.0722*b }'
}

sample() { magick "$1" -format "%[pixel:p{$2,$3}]" info: 2>/dev/null; }

declare -A SIDE LIST HEAD
for mode in light dark; do
    echo "--- switching deploy to $mode ---"
    bash "$SWITCHWALL" --mode "$mode" --noswitch >"$RESULTS/switch-$mode.log" 2>&1
    gs="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d \')"
    check "$mode: gsettings color-scheme is $mode" "$([[ "$gs" == "prefer-$mode" ]] && echo 1 || echo 0)"

    pkill -f '^dolphin' 2>/dev/null || true
    pkill -f '^thunar' 2>/dev/null || true
    sleep 1

    dolphin "$HOME" >"$RESULTS/dolphin-$mode.log" 2>&1 &
    sleep 6
    import -window root "$RESULTS/dolphin-$mode.png" 2>/dev/null
    check "$mode: dolphin screenshot exists" "$([[ -s "$RESULTS/dolphin-$mode.png" ]] && echo 1 || echo 0)"

    SIDE[$mode]="$(sample "$RESULTS/dolphin-$mode.png" 150 400)"
    HEAD[$mode]="$(sample "$RESULTS/dolphin-$mode.png" 500 120)"
    echo "  dolphin sidebar=${SIDE[$mode]} header=${HEAD[$mode]}"
    sl="$(lum "${SIDE[$mode]}")"
    if [[ "$mode" == "light" ]]; then
        check "light: dolphin sidebar is light (lum $sl > 200)" "$([[ "$sl" -gt 200 ]] && echo 1 || echo 0)"
    else
        check "dark: dolphin sidebar is dark (lum $sl < 60)" "$([[ "$sl" -lt 60 ]] && echo 1 || echo 0)"
    fi

    pkill -f '^dolphin' 2>/dev/null || true
    sleep 1
    thunar "$HOME" >"$RESULTS/thunar-$mode.log" 2>&1 &
    sleep 6
    import -window root "$RESULTS/thunar-$mode.png" 2>/dev/null
    check "$mode: thunar screenshot exists" "$([[ -s "$RESULTS/thunar-$mode.png" ]] && echo 1 || echo 0)"
    LIST[$mode]="$(sample "$RESULTS/thunar-$mode.png" 400 300)"
    echo "  thunar list=${LIST[$mode]}"
done

tl="$(lum "${LIST[light]}")"
td="$(lum "${LIST[dark]}")"
delta=$(( tl > td ? tl - td : td - tl ))
check "thunar: light/dark list luminance delta > 80 (light=$tl dark=$td)" \
    "$([[ "$delta" -gt 80 ]] && echo 1 || echo 0)"

sl_l="$(lum "${SIDE[light]}")"
sl_d="$(lum "${SIDE[dark]}")"
delta=$(( sl_l > sl_d ? sl_l - sl_d : sl_d - sl_l ))
check "dolphin: light/dark sidebar luminance delta > 140" "$([[ "$delta" -gt 140 ]] && echo 1 || echo 0)"

echo ""
echo "$pass passed, $fail failed"
echo "screenshots were in $RESULTS (removed on exit)"
[[ "$fail" -eq 0 ]]
