#!/bin/bash
# Generate .desktop files for all installed Android apps

OUTPUT_DIR="${1:-$HOME/.local/share/applications/waydroid}"
mkdir -p "$OUTPUT_DIR"

# Ensure waydroid is running
if ! waydroid status | grep -q "RUNNING"; then
    waydroid session start &
    sleep 3
fi

# Get list of installed packages
waydroid shell pm list packages -3 | sed 's/^package://' | while read -r pkg; do
    # Get launchable activities
    activities=$(waydroid shell pm query-intents --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$pkg" 2>/dev/null | grep -E '^[[:space:]]+' | sed 's/^[[:space:]]*//' | head -1)

    if [ -n "$activities" ]; then
        # Get app label
        label=$(waydroid shell pm list packages -3 -f | grep "$pkg=" | sed 's/.*=//')
        label=${label:-$pkg}

        # Get icon path
        icon_path="$OUTPUT_DIR/$pkg.png"

        cat > "$OUTPUT_DIR/$pkg.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$label
Comment=Android app via Waydroid
Exec=waydroid-app-launcher.sh $pkg
Icon=$icon_path
Terminal=false
Categories=Android;
StartupNotify=true
StartupWMClass=waydroid-$pkg
EOF
    fi
done

# Update desktop database
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true