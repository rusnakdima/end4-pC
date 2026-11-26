#!/usr/bin/env bash
# Regression for tests/qml-compile-check.sh: a syntax error and an unknown
# property must fail the gate, not be filtered out as harmless warnings.
#
# Run:  bash tests/test_qml_compile_check.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SCRIPT_DIR/tests/qml-compile-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/syntax.qml" <<'QML'
pragma ComponentBehavior: Bound
import QtQuick
Item {
    function openPath(path: string, label?: string): void {}
}
QML

cat > "$tmp/property.qml" <<'QML'
pragma ComponentBehavior: Bound
import QtQuick
Item {
    Text { selectByMouse: true }
}
QML

out="$tmp/out"
if bash "$CHECK" "$tmp/syntax.qml" "$tmp/property.qml" > "$out" 2>&1; then
    printf 'FAIL: qml-compile-check accepted broken QML\n' >&2
    cat "$out" >&2
    exit 1
fi

fail=0
for needle in syntax.qml property.qml; do
    if grep -Fq "$needle" "$out"; then
        printf '  OK   %s rejected by the compile gate\n' "$needle"
    else
        printf 'FAIL: %s missing from gate output\n' "$needle" >&2
        fail=1
    fi
done
exit "$fail"
