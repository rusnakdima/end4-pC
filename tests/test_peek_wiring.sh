#!/usr/bin/env bash
# Wiring regressions for the Peek shell service and panel.
#
# Run:  bash tests/test_peek_wiring.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$SCRIPT_DIR/services/Peek.qml"
STATES="$SCRIPT_DIR/GlobalStates.qml"

fail=0
check() {
    local label="$1" file="$2" pattern="$3"
    if grep -qF -- "$pattern" "$file"; then
        printf '  OK   %s\n' "$label"
    else
        printf 'FAIL: %s (missing %q in %s)\n' "$label" "$pattern" "$file" >&2
        fail=1
    fi
}
check_absent() {
    local label="$1" file="$2" pattern="$3"
    if grep -qF -- "$pattern" "$file"; then
        printf 'FAIL: %s (unexpected %q in %s)\n' "$label" "$pattern" "$file" >&2
        fail=1
    else
        printf '  OK   %s\n' "$label"
    fi
}
check_in_function() {
    local label="$1" file="$2" fn="$3" pattern="$4" body
    body="$(sed -n "/function $fn/,/^    }/p" "$file")"
    if printf '%s' "$body" | grep -qF -- "$pattern"; then
        printf '  OK   %s\n' "$label"
    else
        printf 'FAIL: %s (missing %q in %s())\n' "$label" "$pattern" "$fn" >&2
        fail=1
    fi
}

check "Peek IPC handler exists" "$SERVICE" 'IpcHandler'
check "Peek IPC target is peek" "$SERVICE" 'target: "peek"'
check "Peek global shortcut exists" "$SERVICE" 'CompositorGlobalShortcut'
check "Peek shortcut name is peek" "$SERVICE" 'name: "peek"'

check "detect() defined" "$SERVICE" 'function detect()'
check "openPath(path: string) defined" "$SERVICE" 'function openPath(path: string'
check "openText(text: string) defined" "$SERVICE" 'function openText(text: string'
check "edit() defined" "$SERVICE" 'function edit()'
check "toggle() defined" "$SERVICE" 'function toggle()'
check "close() defined" "$SERVICE" 'function close()'
check "zoomIn() defined" "$SERVICE" 'function zoomIn()'
check "zoomOut() defined" "$SERVICE" 'function zoomOut()'
check "resetZoom() defined" "$SERVICE" 'function resetZoom()'

check "detect helper wired via shellPath" "$SERVICE" 'Quickshell.shellPath("features/peek/peek-detect.sh")'
check "edit helper wired via shellPath" "$SERVICE" 'Quickshell.shellPath("features/peek/peek-edit.sh")'
check "text preview cap" "$SERVICE" 'Config.options?.peek?.maxPreviewBytes ?? 262144'
check_in_function "close() resets global overlay state" "$SERVICE" 'close' 'GlobalStates.peekOpen = false'
check "GlobalStates exposes peekOpen" "$STATES" 'property bool peekOpen: false'

check "empty kind" "$SERVICE" '_show("empty"'
check "empty label" "$SERVICE" 'Nothing selected'
check "binary kind" "$SERVICE" '_show("binary"'
check "binary MIME classification" "$SERVICE" 'application/octet-stream'
check "MIME probe" "$SERVICE" 'file --mime-type'
check "capped text read" "$SERVICE" 'head -c'
check "IPC openText exposed" "$SERVICE" 'function openText(text: string): void { root.openText(text) }'
check "IPC edit exposed" "$SERVICE" 'function edit(): void { root.edit() }'

exit "$fail"
