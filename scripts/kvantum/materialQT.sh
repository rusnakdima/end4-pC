#!/usr/bin/env bash

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
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

	# MaterialAdw is the generated destination, never its own source. If
	# detection found no source theme, keep the existing generated files.
	if [[ -z "$source_dir" || "$source_dir" == "$theme_name" ]]; then
		return 0
	fi

	local kv_roots="${APP_THEMING_KVANTUM_ROOTS:-$XDG_CONFIG_HOME/Kvantum:$XDG_DATA_HOME/Kvantum:/usr/share/Kvantum}"
	local kv_root_list=() base
	IFS=: read -ra kv_root_list <<< "$kv_roots"
	local folder_path=""
	for base in "${kv_root_list[@]}"; do
		if [[ -d "$base/$source_dir" ]] \
			&& { [[ -f "$base/$source_dir/$light_source" ]] || [[ -f "$base/$source_dir/$dark_source" ]]; }; then
			folder_path="$base/$source_dir/"
			break
		fi
	done
	local destination="$XDG_CONFIG_HOME/Kvantum/$theme_name/$theme_name.kvconfig"

	if [[ -z "$folder_path" ]]; then
		if [ "${APP_THEMING_NO_EXTERNAL:-0}" != 1 ]; then
			notify-send "Kvantum source theme required" "No folder for '$source_dir' was found in $kv_roots."
		fi
		return 1
	fi

	mkdir -p "$(dirname "$destination")"
	lightdark=$(get_light_dark)
	local source_file
	if [ "$lightdark" = "light" ]; then
		source_file="$folder_path/$light_source"
		[[ -f "$source_file" ]] || return 0
		cp "$source_file" "$destination"
		python "$CONFIG_DIR/scripts/kvantum/adwsvg.py"
	else
		source_file="$folder_path/$dark_source"
		[[ -f "$source_file" ]] || return 0
		cp "$source_file" "$destination"
		python "$CONFIG_DIR/scripts/kvantum/adwsvgDark.py"
	fi
}

apply_qt
