#!/usr/bin/env bash
# Contract test: --theme-only refreshes greeter QML without touching SDDM config.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
HELPER="$ROOT/scripts/sddm/deploy-theme.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/src/sddm/ii-sddm-theme/Components" \
         "$tmp/theme/Components" "$tmp/home"
printf 'patched input\n' > "$tmp/src/sddm/ii-sddm-theme/Components/Input.qml"
printf 'patched user button\n' > "$tmp/src/sddm/ii-sddm-theme/Components/UserButton.qml"
printf 'fork settings\n' > "$tmp/src/sddm/ii-sddm-theme/Components/Settings.qml"
printf 'old input\n' > "$tmp/theme/Components/Input.qml"
printf 'old user button\n' > "$tmp/theme/Components/UserButton.qml"
printf 'device settings\n' > "$tmp/theme/Components/Settings.qml"
printf '[Theme]\nCurrent=ii-sddm-theme\nDisplayServer=keep-me\n' > "$tmp/ii-sddm-theme.conf"
cp "$tmp/ii-sddm-theme.conf" "$tmp/ii-sddm-theme.conf.before"

"$HELPER" --help | grep -q -- '--theme-only' ||
    fail '--theme-only is not documented in helper usage'

END4PC_SOURCE_DIR="$tmp/src" \
END4PC_SDDM_THEME_DIR="$tmp/theme" \
END4PC_SDDM_CONF="$tmp/ii-sddm-theme.conf" \
END4PC_TARGET_HOME="$tmp/home" \
END4PC_ELEVATE= \
"$HELPER" --theme-only

grep -q 'patched user button' "$tmp/theme/Components/UserButton.qml" ||
    fail '--theme-only did not deploy patched QML'
grep -q 'device settings' "$tmp/theme/Components/Settings.qml" ||
    fail '--theme-only overwrote generated device settings'
cmp -s "$tmp/ii-sddm-theme.conf" "$tmp/ii-sddm-theme.conf.before" ||
    fail '--theme-only modified the SDDM config drop-in'

echo 'PASS: --theme-only deploys QML without rewriting SDDM config'
