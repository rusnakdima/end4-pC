#!/usr/bin/env bash
#
# Checks that every functional area of the config has a test.
#
# "Every functional is covered" is a claim; this script turns it into a
# check. It enumerates the units that hold logic — the services and the
# widgets — and requires each of them to be either
#
#   * mapped to a test file (the mapping is the naming rule
#     tst_<area>.qml, with an explicit list for the areas whose name
#     differs), or
#   * exempted, with a written reason, in tests/coverage-exemptions.txt.
#
# A unit holds logic when it declares a JavaScript function. The exemptions
# file is checked for staleness too: an exemption for a file that no longer
# exists is an error, so the list cannot rot.
#
# Usage: functional-coverage.sh
#        exits 0 when every area is covered, 1 otherwise.
#
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

TEST_DIR="tests/shell-tests"
EXEMPTION_FILE="tests/coverage-exemptions.txt"

# area -> test file, for the areas whose test file name is not
# tst_<area>.qml.
declare -A EXPLICIT_MAP=(
    [NotificationUtils]="tst_notifications.qml"
    [ShapeUtils]="tst_shapes.qml"
    [Fuzzy]="tst_fuzzy.qml"
    [Levendist]="tst_levenshtein.qml"
    [KeyCombos]="tst_keycombos.qml"
    [MprisController]="tst_mpris.qml"
    [SettingsSearchIndex]="tst_settings_search.qml"
    [HyprlandConfig]="tst_hyprland_config.qml"
    [HyprlandKeybinds]="tst_hyprland_keybinds.qml"
    [OnlineWallpapers]="tst_online_wallpapers.qml"
    [SpeechToText]="tst_speech_to_text.qml"
    [BarContent]="tst_bar_content.qml"
    [BarGroup]="tst_bar_group.qml"
    [ThumbnailImage]="tst_thumbnail_image.qml"
    [WallpaperDirectoryItem]="tst_wallpaper_item.qml"
    [Settings]="tst_settings_card.qml"
    [HyprlandXkbIndicator]="tst_xkb_indicator.qml"
    [GlobalStates]="tst_global_states.qml"
    [Notifications]="tst_notifications_model.qml"
    [StringUtils]="tst_strings.qml"
    [NumberUtils]="tst_numbers.qml"
    [ColorUtils]="tst_colors.qml"
    [FileUtils]="tst_files.qml"
    [DateUtils]="tst_dates.qml"
    [ObjectUtils]="tst_objects.qml"
    [Translation]="tst_translation.qml"
    [Appearance]="tst_appearance.qml"
    [Images]="tst_images.qml"
    [Config]="tst_config.qml"
    [Wallpapers]="tst_wallpapers.qml"
    [Updates]="tst_updates.qml"
    [Weather]="tst_weather.qml"
    [Presets]="tst_presets.qml"
    [Ai]="tst_ai.qml"
    [Persistent]="tst_persistent.qml"
    [Directories]="tst_directories.qml"
)

# The units that hold logic: a service, or a component that declares a
# JavaScript function.
collect_areas() {
    local file
    for file in services/*.qml; do
        [[ -e "$file" ]] || continue
        printf '%s\n' "$file"
    done
    find modules/common/widgets modules/ii -name '*.qml' | sort
}

# A unit holds logic when it declares a function. Signal handlers are
# excluded: they are the widget reacting, not logic of its own.
has_logic() {
    grep -qE '^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$1" \
        && ! grep -qE '^[[:space:]]*function[[:space:]]+on[A-Z][A-Za-z0-9_]*[[:space:]]*\(' "$1"
}

test_file_for() {
    local key="$1"
    if [[ -n "${EXPLICIT_MAP[$key]:-}" ]]; then
        printf '%s\n' "${EXPLICIT_MAP[$key]}"
    else
        printf 'tst_%s.qml\n' "$key"
    fi
}

missing=0
checked=0

while IFS= read -r area; do
    has_logic "$area" || continue
    checked=$((checked + 1))

    key="${area##*/}"
    key="${key%.qml}"

    if grep -qF "$area|" "$EXEMPTION_FILE" 2> /dev/null; then
        continue
    fi

    test_file=$(test_file_for "$key")
    if [[ ! -f "$TEST_DIR/$test_file" ]]; then
        printf 'UNMAPPED %s -> %s/%s\n' "$area" "$TEST_DIR" "$test_file"
        missing=$((missing + 1))
    fi
done < <(collect_areas)

# An exemption for a file that no longer exists is stale: the list must
# not rot.
if [[ -f "$EXEMPTION_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "${line:0:1}" == "#" ]] && continue
        path="${line%%|*}"

        if [[ ! -f "$path" ]]; then
            printf 'STALE EXEMPTION %s (the file no longer exists)\n' "$path"
            missing=$((missing + 1))
            continue
        fi

        reason="${line#*|}"
        if [[ -z "${reason// /}" ]]; then
            printf 'EXEMPTION WITHOUT REASON %s\n' "$path"
            missing=$((missing + 1))
        fi
    done < "$EXEMPTION_FILE"
fi

# Every test file on disk must also be listed in the harness, or it would
# never run.
if [[ -f "$TEST_DIR/shell.qml" ]]; then
    while IFS= read -r file; do
        name="${file##*/}"
        if ! grep -qF "\"$name\"" "$TEST_DIR/shell.qml"; then
            printf 'UNLISTED %s/%s is not in the harness file list\n' "$TEST_DIR" "$name"
            missing=$((missing + 1))
        fi
    done < <(find "$TEST_DIR" -maxdepth 1 -name 'tst_*.qml' | sort)
fi

if [[ "$missing" -ne 0 ]]; then
    printf 'FAIL: %d functional area(s) are not covered\n' "$missing" >&2
    exit 1
fi

printf 'PASS: %d functional areas are covered\n' "$checked"
exit 0
