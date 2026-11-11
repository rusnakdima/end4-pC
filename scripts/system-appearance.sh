#!/usr/bin/env bash
# system-appearance.sh - list and apply system icons, cursors and fonts (Qt via kdeglobals/kcminputrc + GTK via gsettings)
# Usage:
#   system-appearance.sh --list-icons | --list-cursors | --list-fonts
#   system-appearance.sh --get
#   system-appearance.sh --set-icons <theme>
#   system-appearance.sh --set-cursor <theme> <size>
#   system-appearance.sh --set-font <ui|mono> <family> <size>
#   system-appearance.sh --apply-cursor

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
ICON_DIRS=(/usr/share/icons "$DATA_HOME/icons" "$HOME/.icons")

theme_dirs() {
    for dir in "${ICON_DIRS[@]}"; do
        [ -d "$dir" ] && find -L "$dir" -mindepth 1 -maxdepth 1 -type d
    done
}

notify_qt() {
    dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:"$1" int32:"$2" 2>/dev/null
}

read_cursor() {
    cursor_theme=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme)
    cursor_size=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorSize)
    [ -z "$cursor_theme" ] && cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
    [ -z "$cursor_size" ] && cursor_size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null)
    [ -z "$cursor_size" ] && cursor_size=24
}

apply_cursor() {
    hyprctl setcursor "$1" "$2" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface cursor-theme "$1" 2>/dev/null
    gsettings set org.gnome.desktop.interface cursor-size "$2" 2>/dev/null
    mkdir -p "$HOME/.icons/default"
    printf '[Icon Theme]\nName=Default\nInherits=%s\n' "$1" > "$HOME/.icons/default/index.theme"
}

replace_font_field() {
    awk -F, -v OFS=, -v family="$1" -v size="$2" '{ $1 = family; $2 = size; print }'
}

set_qt_font() {
    local key="$1" family="$2" size="$3" current
    current=$(kreadconfig6 --file kdeglobals --group General --key "$key")
    [ -z "$current" ] && current="$family,$size,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --notify --file kdeglobals --group General --key "$key" "$(echo "$current" | replace_font_field "$family" "$size")"
}

# Qt5 font settings
set_qt5_font() {
    local key="$1" family="$2" size="$3"
    local conf="$HOME/.config/qt5ct/qt5ct.conf"
    mkdir -p "$(dirname "$conf")"
    if grep -q "^${key}=" "$conf" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${family},${size}|" "$conf"
    else
        echo "${key}=${family},${size}" >> "$conf"
    fi
}

# GTK font-name in settings.ini
set_gtk_font_name() {
    local family="$1" size="$2"
    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        mkdir -p "$(dirname "$f")"
        if grep -q "^gtk-font-name=" "$f" 2>/dev/null; then
            sed -i "s|^gtk-font-name=.*|gtk-font-name=${family} ${size}|" "$f"
        else
            echo "gtk-font-name=${family} ${size}" >> "$f"
        fi
    done
}

# GTK icon-theme-name in settings.ini. GTK3 apps and Qt's gtk3 platform
# theme read this file, so without it the icon theme the shell applies in
# kdeglobals and the one toolkits use silently diverge.
set_gtk_icon_theme() {
    local theme="$1" f
    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        if [ ! -f "$f" ]; then
            mkdir -p "$(dirname "$f")"
            printf '[Settings]\ngtk-icon-theme-name=%s\n' "$theme" > "$f"
        elif grep -q "^gtk-icon-theme-name=" "$f"; then
            sed -i "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=${theme}|" "$f"
        elif grep -q "^\[Settings\]" "$f"; then
            sed -i "/^\[Settings\]/a gtk-icon-theme-name=${theme}" "$f"
        else
            printf '\n[Settings]\ngtk-icon-theme-name=%s\n' "$theme" >> "$f"
        fi
    done
}

# Terminal mono font sync (kitty)
sync_terminal_mono_font() {
    local family="$1" size="$2"
    local kitty_conf="$HOME/.config/kitty/kitty.conf"
    if [ -f "$kitty_conf" ]; then
        if grep -q "^font_family" "$kitty_conf" 2>/dev/null; then
            sed -i "s|^font_family.*|font_family ${family}|" "$kitty_conf"
        else
            echo "font_family ${family}" >> "$kitty_conf"
        fi
        if grep -q "^font_size" "$kitty_conf" 2>/dev/null; then
            sed -i "s|^font_size.*|font_size ${size}.0|" "$kitty_conf"
        else
            echo "font_size ${size}.0" >> "$kitty_conf"
        fi
    fi
}

# Terminal UI font sync (kitty)
sync_terminal_ui_font() {
    local family="$1" size="$2"
    local kitty_conf="$HOME/.config/kitty/kitty.conf"
    if [ -f "$kitty_conf" ]; then
        if grep -q "^font_family" "$kitty_conf" 2>/dev/null; then
            sed -i "s|^font_family.*|font_family ${family}|" "$kitty_conf"
        else
            echo "font_family ${family}" >> "$kitty_conf"
        fi
        if grep -q "^font_size" "$kitty_conf" 2>/dev/null; then
            sed -i "s|^font_size.*|font_size ${size}.0|" "$kitty_conf"
        else
            echo "font_size ${size}.0" >> "$kitty_conf"
        fi
    fi
}

# Hyprlock font sync - updates colors.conf variables
sync_hyprlock_font() {
    local family="$1" size="$2"
    local colors_conf="$HOME/.config/hypr/hyprlock/colors.conf"
    if [ -f "$colors_conf" ]; then
        sed -i 's|^\$font_family = .*|$font_family = '"${family}"'|' "$colors_conf"
        sed -i 's|^\$font_family_clock = .*|$font_family_clock = '"${family}"'|' "$colors_conf"
    fi
}

action="$1"
shift

case "$action" in
    --list-icons)
        theme_dirs | while read -r dir; do
            name=$(basename "$dir")
            case "$name" in default|hicolor) continue ;; esac
            [ -f "$dir/index.theme" ] && grep -q "^Directories=" "$dir/index.theme" && echo "$name"
        done | grep -Ev -- '-Dynamic-' | sort -u
        ;;
    --list-cursors)
        theme_dirs | while read -r dir; do
            [ -d "$dir/cursors" ] && basename "$dir"
        done | sort -u
        ;;
    --list-fonts)
        fc-list : family | sed 's/,.*//' | sort -u
        ;;
    --get)
        read_cursor
        jq -n \
            --arg icons "$(kreadconfig6 --file kdeglobals --group Icons --key Theme)" \
            --arg cursor "$cursor_theme" \
            --argjson cursorSize "${cursor_size:-24}" \
            --arg font "$(kreadconfig6 --file kdeglobals --group General --key font)" \
            --arg mono "$(kreadconfig6 --file kdeglobals --group General --key fixed)" \
            '{
                icons: $icons,
                cursor: $cursor,
                cursorSize: $cursorSize,
                fontFamily: ($font | split(",")[0]),
                fontSize: (($font | split(",")[1]) // "11" | tonumber? // 11),
                monoFamily: ($mono | split(",")[0]),
                monoSize: (($mono | split(",")[1]) // "11" | tonumber? // 11)
            }'
        ;;
    --set-icons)
        kwriteconfig6 --notify --file kdeglobals --group Icons --key Theme "$1"
        gsettings set org.gnome.desktop.interface icon-theme "$1" 2>/dev/null
        set_gtk_icon_theme "$1"
        notify_qt 4 0
        ;;
    --set-cursor)
        kwriteconfig6 --notify --file kcminputrc --group Mouse --key cursorTheme "$1"
        kwriteconfig6 --notify --file kcminputrc --group Mouse --key cursorSize "$2"
        apply_cursor "$1" "$2"
        notify_qt 5 0
        ;;
    --apply-cursor)
        read_cursor
        apply_cursor "$cursor_theme" "$cursor_size"
        ;;
    --set-font)
        role="$1"; family="$2"; size="$3"
        if [ "$role" = "mono" ]; then
            set_qt_font fixed "$family" "$size"
            gsettings set org.gnome.desktop.interface monospace-font-name "$family $size" 2>/dev/null
            # Qt5 monospace font
            set_qt5_font fixed "$family" "$size"
            # Terminal mono font sync
            sync_terminal_mono_font "$family" "$size"
        else
            for key in font menuFont toolBarFont; do set_qt_font "$key" "$family" "$size"; done
            set_qt_font smallestReadableFont "$family" "$((size > 2 ? size - 2 : size))"
            gsettings set org.gnome.desktop.interface font-name "$family $size" 2>/dev/null
            # Qt5 UI font
            set_qt5_font font "$family" "$size"
            # GTK font-name in settings.ini
            set_gtk_font_name "$family" "$size"
            # Terminal UI font sync
            sync_terminal_ui_font "$family" "$size"
            # Hyprlock font sync
            sync_hyprlock_font "$family" "$size"
        fi
        ;;
    *)
        echo "Error: unknown action: $action" >&2
        exit 1
        ;;
esac
