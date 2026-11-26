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
check "IPC openText exposed" "$SERVICE" 'function openText(text: string): void { root.openText(text, "") }'
check "IPC edit exposed" "$SERVICE" 'function edit(): void { root.edit() }'
check_absent "no optional QML parameters" "$SERVICE" 'label?: string'
check "notfound kind" "$SERVICE" '_show("notfound"'
check "notfound label" "$SERVICE" 'File not found:'
check "edit failures surfaced" "$SERVICE" 'Could not open editor:'

# Panel wiring (Task 4)
SCOPE="$SCRIPT_DIR/modules/ii/peek/Peek.qml"
PANEL="$SCRIPT_DIR/modules/ii/peek/PeekPanel.qml"
FAMILY_II="$SCRIPT_DIR/panelFamilies/IllogicalImpulseFamily.qml"
FAMILY_WAFFLE="$SCRIPT_DIR/panelFamilies/WaffleFamily.qml"

check_absent_re() {
    local label="$1" file="$2" pattern="$3"
    if grep -qE -- "$pattern" "$file" 2>/dev/null; then
        printf 'FAIL: %s (unexpected pattern %q in %s)\n' "$label" "$pattern" "$file" >&2
        fail=1
    else
        printf '  OK   %s\n' "$label"
    fi
}

check "scope Loader gated on peekOpen" "$SCOPE" 'active: Config.ready && GlobalStates.peekOpen'
if sed -n '/Component.onCompleted:/,/^    }/p' "$SCOPE" | grep -qF 'GlobalStates.peekOpen = false'; then
    printf '  OK   scope resets stuck overlay\n'
else
    printf 'FAIL: scope resets stuck overlay (missing reset in Component.onCompleted)\n' >&2
    fail=1
fi
check "panel title is Peek" "$PANEL" 'title: "Peek"'
check_absent "panel has no Qt5-only selectByMouse" "$PANEL" 'selectByMouse'
check "panel shows notfound hint" "$PANEL" 'Peek.kind === "notfound"'
check "panel closes with the service" "$PANEL" 'onClosing: event => Peek.close()'
check "panel handles Escape" "$PANEL" 'Qt.Key_Escape'
check "panel handles E" "$PANEL" 'Qt.Key_E'
check "panel has an edit action" "$PANEL" 'Peek.edit()'
check "panel handles plus/equal" "$PANEL" 'Qt.Key_Plus'
check "panel handles equal" "$PANEL" 'Qt.Key_Equal'
check "panel handles minus" "$PANEL" 'Qt.Key_Minus'
check "panel handles zero" "$PANEL" 'Qt.Key_0'
check "scope imports peek module" "$SCOPE" 'import qs.modules.ii.peek'
check "family II imports peek module" "$FAMILY_II" 'import qs.modules.ii.peek'
check "family waffle imports peek module" "$FAMILY_WAFFLE" 'import qs.modules.ii.peek'
check "family II registers Peek" "$FAMILY_II" 'PanelLoader { component: Peek {} }'
check "family waffle registers Peek" "$FAMILY_WAFFLE" 'PanelLoader { component: Peek {} }'
check_absent_re "scope has no hardcoded hex colours" "$SCOPE" '#[0-9a-fA-F]{3,8}'
check_absent_re "panel has no hardcoded hex colours" "$PANEL" '#[0-9a-fA-F]{3,8}'

exit "$fail"
