#!/usr/bin/env bash
# Apply icon theme system-wide. Usage: set-icon-theme.sh <theme>
# Ported from the rofi settings-menu script (gsettings + gtk2/3/4 + xsettingsd + rofi).
set -u

theme="$1"
[[ -z "$theme" ]] && { echo "usage: $0 <icon-theme>" >&2; exit 1; }

set_ini_key() { # file key value
    local file="$1" key="$2" value="$3"
    mkdir -p "$(dirname "$file")"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        [[ -f "$file" ]] || echo "[Settings]" >"$file"
        echo "${key}=${value}" >>"$file"
    fi
}

# Rofi
mkdir -p "$HOME/.config/rofi/themes"
cat >"$HOME/.config/rofi/themes/icons.rasi" <<EOF
* {
  icon-theme: "$theme";
}
EOF

gsettings set org.gnome.desktop.interface icon-theme "$theme" 2>/dev/null

set_ini_key "$HOME/.config/gtk-3.0/settings.ini" gtk-icon-theme-name "$theme"
set_ini_key "$HOME/.config/gtk-4.0/settings.ini" gtk-icon-theme-name "$theme"

# Qt5/Qt6 icon theme
set_ini_key "$HOME/.config/qt5ct/qt5ct.conf" icon_theme "$theme"
set_ini_key "$HOME/.config/qt6ct/qt6ct.conf" icon_theme "$theme"

# GTK 2
GTK2_CONFIG="$HOME/.gtkrc-2.0"
if grep -q "^gtk-icon-theme-name=" "$GTK2_CONFIG" 2>/dev/null; then
    sed -i "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=\"$theme\"|" "$GTK2_CONFIG"
else
    echo "gtk-icon-theme-name=\"$theme\"" >>"$GTK2_CONFIG"
fi

# xsettingsd for X11/XWayland apps
XSETTINGSD_CONFIG="$HOME/.config/xsettingsd/xsettingsd.conf"
mkdir -p "$(dirname "$XSETTINGSD_CONFIG")"
if grep -q "^Net/IconThemeName" "$XSETTINGSD_CONFIG" 2>/dev/null; then
    sed -i "s|^Net/IconThemeName.*|Net/IconThemeName \"$theme\"|" "$XSETTINGSD_CONFIG"
else
    echo "Net/IconThemeName \"$theme\"" >>"$XSETTINGSD_CONFIG"
fi
pkill -HUP xsettingsd 2>/dev/null

# xsettingsd font settings (X11/XWayland apps)
XSETTINGSD_CONFIG="$HOME/.config/xsettingsd/xsettingsd.conf"
mkdir -p "$(dirname "$XSETTINGSD_CONFIG")"
if grep -q "^Xft/Antialias" "$XSETTINGSD_CONFIG" 2>/dev/null; then
    sed -i "s|^Xft/Antialias.*|Xft/Antialias 1|" "$XSETTINGSD_CONFIG"
else
    echo "Xft/Antialias 1" >> "$XSETTINGSD_CONFIG"
fi
if grep -q "^Xft/Hinting" "$XSETTINGSD_CONFIG" 2>/dev/null; then
    sed -i "s|^Xft/Hinting.*|Xft/Hinting 1|" "$XSETTINGSD_CONFIG"
else
    echo "Xft/Hinting 1" >> "$XSETTINGSD_CONFIG"
fi
if grep -q "^Xft/HintStyle" "$XSETTINGSD_CONFIG" 2>/dev/null; then
    sed -i "s|^Xft/HintStyle.*|Xft/HintStyle \"hintslight\"|" "$XSETTINGSD_CONFIG"
else
    echo "Xft/HintStyle \"hintslight\"" >> "$XSETTINGSD_CONFIG"
fi
if grep -q "^Xft/RGBA" "$XSETTINGSD_CONFIG" 2>/dev/null; then
    sed -i "s|^Xft/RGBA.*|Xft/RGBA \"rgb\"|" "$XSETTINGSD_CONFIG"
else
    echo "Xft/RGBA \"rgb\"" >> "$XSETTINGSD_CONFIG"
fi
pkill -HUP xsettingsd 2>/dev/null

exit 0
