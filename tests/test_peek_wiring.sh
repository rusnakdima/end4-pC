#!/usr/bin/env bash
# Wiring regressions for the Peek shell service and panel.
#
# Run:  bash tests/test_peek_wiring.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$SCRIPT_DIR/services/Peek.qml"
STATES="$SCRIPT_DIR/GlobalStates.qml"
SHELL="$SCRIPT_DIR/shell.qml"

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
check "copy helper wired via shellPath" "$SERVICE" 'Quickshell.shellPath("features/peek/peek-copy.sh")'
check "copyImage() defined" "$SERVICE" 'function copyImage()'
check "copyPath() defined" "$SERVICE" 'function copyPath()'
check "copyImage copies image pixels" "$SERVICE" 'copyScript)} image'
check "copyPath copies the path" "$SERVICE" 'copyScript)} path'
check "copy feedback is surfaced" "$SERVICE" 'property string actionMessage'
check "IPC copyImage exposed" "$SERVICE" 'function copyImage(): void { root.copyImage() }'
check "IPC copyPath exposed" "$SERVICE" 'function copyPath(): void { root.copyPath() }'
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
check "selected paths auto-open in nvim" "$SERVICE" 'root.openPath(fields[1], fields[2], autoEdit)'
check_in_function "selected text does not preview" "$SERVICE" detect 'fields[2] === "Selected text"'
check_in_function "editable paths auto-open the editor" "$SERVICE" 'openPath' 'if (autoEdit)'
check "IPC openPath disables auto-edit" "$SERVICE" 'function openPath(path: string): void { root.openPath(path, "", false) }'
check_in_function "editor success closes the overlay" "$SERVICE" '_openInEditor' 'root.close()'

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
if sed -n '/id: deferredInitTimer/,/^        }/p' "$SHELL" | grep -qF 'Peek.close();'; then
    printf '  OK   shell forces lazy Peek singleton at startup\n'
else
    printf 'FAIL: shell forces lazy Peek singleton (missing Peek.close() in deferred init)\n' >&2
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

check "image viewer helper wired via shellPath" "$SERVICE" 'features/peek/peek-image.sh'
check "image viewer function defined" "$SERVICE" 'function _openInViewer(path: string, label: string): void'
check_in_function "edit() sends images to swappy" "$SERVICE" edit 'root._openInViewer(root.sourcePath, root.displayLabel)'
check_in_function "detected images auto-open in swappy" "$SERVICE" openPath 'if (autoEdit) { root._openInViewer(clean, name); return; }'
check_in_function "IPC image preview stays available" "$SERVICE" openPath 'root._show("image", clean, name, "")'
check_in_function "edit() keeps nvim for files" "$SERVICE" edit 'root._openInEditor(root.sourcePath, root.displayLabel)'
check_in_function "plain selected text is skipped" "$SERVICE" detect 'fields[2] === "Selected text"'
check_in_function "plain clipboard text is skipped" "$SERVICE" detect 'fields[2] === "Clipboard text"'
check_in_function "skipped selections close the overlay" "$SERVICE" detect 'root.close()'

exit "$fail"
