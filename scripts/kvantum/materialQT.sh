#!/usr/bin/env bash

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Derive the config root from this script's location so the same file works
# from the repo, from an installed end4-pC config, and under the test harness.
CONFIG_DIR="${APP_THEMING_SCRIPT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
RESOLVED_FILE="${APP_THEMING_RESOLVED_FILE:-$STATE_DIR/theme-stack/resolved.json}"

resolved_value() {
	local key="$1" fallback="$2" value
	value="$(jq -r ".$key // empty" "$RESOLVED_FILE" 2>/dev/null)"
	printf '%s' "${value:-$fallback}"
}

get_light_dark() {
	current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
	if [[ "$current_mode" == "prefer-dark" ]]; then
		echo "dark"
	else
		echo "light"
	fi
}

apply_qt() {
	# Both the source theme and the generated destination come from the resolved
	# map written by theme-provision.sh, with the historical roles as fallback.
	local source_dir theme_name light_source dark_source
	source_dir="$(resolved_value kvantumSourceDir Colloid)"
	theme_name="$(resolved_value kvantumTheme MaterialAdw)"
	light_source="$(resolved_value kvantumLightSource Colloid.kvconfig)"
	dark_source="$(resolved_value kvantumDarkSource ColloidDark.kvconfig)"

	local folder_path="$XDG_CONFIG_HOME/Kvantum/$source_dir/"
	local destination="$XDG_CONFIG_HOME/Kvantum/$theme_name/$theme_name.kvconfig"

	if [ ! -d "$folder_path" ]; then
		if [ "${APP_THEMING_NO_EXTERNAL:-0}" != 1 ]; then
			notify-send "Kvantum source theme required" " The folder '$folder_path' does not exist."
		fi
		exit 1 # Exit the function if the folder does not exist
	fi

	mkdir -p "$(dirname "$destination")"
	lightdark=$(get_light_dark)
	if [ "$lightdark" = "light" ]; then
		cp "$folder_path/$light_source" "$destination"
		python "$CONFIG_DIR/scripts/kvantum/adwsvg.py"
	else
		cp "$folder_path/$dark_source" "$destination"
		python "$CONFIG_DIR/scripts/kvantum/adwsvgDark.py"
	fi
}

apply_qt
