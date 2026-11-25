#!/bin/bash
# Generate .desktop files for installed Android apps (user mode, no sudo).
#
# `waydroid shell pm ...` is root-gated. `waydroid app list` talks to the
# user's session over D-Bus and returns "Name:" / "packageName:" rows instead.

OUTPUT_DIR="${1:-$HOME/.local/share/applications}"
mkdir -p "$OUTPUT_DIR"

# Make sure the session is up without sudo; fail fast instead of hanging in
# `waydroid app list` with "Failed to get service waydroidplatform".
helper=$(command -v waydroid-user-start 2>/dev/null || true)
if [ -z "$helper" ] || [ ! -x "$helper" ]; then
    helper="$HOME/.local/bin/waydroid-user-start"
fi
if [ ! -x "$helper" ]; then
    helper="$(cd "$(dirname "$0")" && pwd)/waydroid-user-start"
fi
if [ -x "$helper" ]; then
    "$helper" || exit 1
fi

list=$(timeout 40 waydroid app list 2>/dev/null || true)

printf '%s\n' "$list" | awk '
    /^Name:/ { name = substr($0, 6); sub(/^[[:space:]]*/, "", name); next }
    /^packageName:/ {
        pkg = substr($0, 13); sub(/^[[:space:]]*/, "", pkg)
        if (pkg != "") printf "%s\t%s\n", pkg, (name == "" ? pkg : name)
        name = ""
    }
' | while IFS=$'\t' read -r pkg label; do
    desktop="$OUTPUT_DIR/waydroid.$pkg.desktop"
    icon="$HOME/.local/share/waydroid/data/icons/$pkg.png"
    [ -f "$icon" ] || icon="waydroid"
    launcher="$(cd "$(dirname "$0")" && pwd)/waydroid-app-launcher.sh"

    cat > "$desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$label
Comment=Android app via Waydroid
Exec=$launcher $pkg
Icon=$icon
Terminal=false
Categories=Android;
StartupNotify=true
StartupWMClass=waydroid-$pkg
EOF
done

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
