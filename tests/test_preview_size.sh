#!/usr/bin/env bash
# Image preview panels must size their card to 75% of the screen.
#
# Run:  bash tests/test_preview_size.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PEEK_PANEL="$SCRIPT_DIR/modules/ii/peek/PeekPanel.qml"
IMAGE_PANEL="$SCRIPT_DIR/modules/ii/imagePreview/ImagePreviewPanel.qml"

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

# Quickshell's ShellScreen exposes x/y/width/height directly; `.geometry` is
# undefined and made both windows fall back to a 500x500 default.
for panel in "$PEEK_PANEL" "$IMAGE_PANEL"; do
    name="$(basename "$panel")"
    check_absent "$name has no invalid screen.geometry access" "$panel" 'screen.geometry'
    check "$name window x uses ShellScreen.x" "$panel" 'root.screen ? root.screen.x : 0'
    check "$name window y uses ShellScreen.y" "$panel" 'root.screen ? root.screen.y : 0'
    check "$name window width uses ShellScreen.width" "$panel" 'root.screen ? root.screen.width : 1280'
    check "$name window height uses ShellScreen.height" "$panel" 'root.screen ? root.screen.height : 800'
done

# An image preview is a bare 75% image block: no header, no inner margins, no
# card chrome. Other Peek kinds keep the normal labelled card.
check "Peek image-only mode follows the image kind" "$PEEK_PANEL" 'property bool imageOnly: Peek.kind === "image"'
check "Peek image-only card has no margins" "$PEEK_PANEL" 'margins: imageOnly ? 0 : 10'
check "Peek hides the header in image-only mode" "$PEEK_PANEL" 'visible: !imageOnly'
check "Peek image-only card has no radius" "$PEEK_PANEL" 'radius: imageOnly ? 0 : Appearance.rounding.verylarge'
check "Peek image-only card has no border" "$PEEK_PANEL" 'border.width: imageOnly ? 0 : 1'

check "Peek card width is 75% of the screen" "$PEEK_PANEL" 'Math.round(root.width * 0.75)'
check "Peek card height is 75% of the screen" "$PEEK_PANEL" 'Math.round(root.height * 0.75)'
check "Peek image card uses the 75% width" "$PEEK_PANEL" 'card.width = previewWidth'
check "Peek image card uses the 75% height" "$PEEK_PANEL" 'card.height = previewHeight'
check "Peek zoom scales the image inside the card" "$PEEK_PANEL" 'scale: Peek.fitMode ? 1 : Peek.zoom'

check "Image Preview card width is 75% of the screen" "$IMAGE_PANEL" 'Math.round(root.width * 0.75)'
check "Image Preview card height is 75% of the screen" "$IMAGE_PANEL" 'Math.round(root.height * 0.75)'
check "Image Preview card uses the 75% width" "$IMAGE_PANEL" 'card.width = previewWidth'
check "Image Preview card uses the 75% height" "$IMAGE_PANEL" 'card.height = previewHeight'
check "Image Preview zoom scales the image inside the card" "$IMAGE_PANEL" 'scale: ImagePreview.fitMode ? 1 : ImagePreview.zoom'

if bash "$SCRIPT_DIR/tests/qml-compile-check.sh" "$PEEK_PANEL" "$IMAGE_PANEL" >/dev/null; then
    printf '  OK   both preview panels compile\n'
else
    printf 'FAIL: preview panels do not compile\n' >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi
printf 'Preview size checks passed\n'
