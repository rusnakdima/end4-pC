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
