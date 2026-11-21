#!/usr/bin/env bash
# Regression test: the visualizer's cava config must capture the monitor of
# the default output, not the system default capture device (microphone).
#
# With no [input] section, cava's "auto" source resolves to the mic on
# PipeWire setups with a Bluetooth headset + EasyEffects, so the bar/desktop
# visualizer reacted to speech instead of the music being played.
#
# Run:  bash tests/test_cava_source.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$SCRIPT_DIR/scripts/cava/raw_output_config.txt"

[[ -f "$CONFIG" ]] || { echo "FAIL: $CONFIG missing"; exit 1; }

# Cava keys are "key = value"; only read the [input] section, skip comments.
value_of() {
    awk -v key="$1" '
        /^[[:space:]]*\[/ { section = $0; gsub(/[[:space:]]/, "", section); next }
        section != "[input]" { next }
        /^[[:space:]]*($|#|;)/ { next }
        $1 == key && $2 == "=" { $1 = ""; $2 = ""; sub(/^[[:space:]]+/, ""); print; exit }
    ' "$CONFIG"
}

fail=0
check() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL: %s: expected %q, got %q\n' "$label" "$expected" "$actual" >&2
        fail=1
    else
        printf '  OK   %s = %s\n' "$label" "$actual"
    fi
}

check "input method" "$(value_of method)" "pulse"
check "input source" "$(value_of source)" "@DEFAULT_SINK@.monitor"

exit "$fail"
