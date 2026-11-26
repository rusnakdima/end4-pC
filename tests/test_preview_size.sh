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
    check "$name window x uses ShellScreen.x" "$panel" 'root.screen.x !== undefined ? root.screen.x : 0'
    check "$name window y uses ShellScreen.y" "$panel" 'root.screen.y !== undefined ? root.screen.y : 0'
    check "$name window width uses ShellScreen.width" "$panel" 'root.screen.width !== undefined ? root.screen.width : 1280'
    check "$name window height uses ShellScreen.height" "$panel" 'root.screen.height !== undefined ? root.screen.height : 800'
done

# The preview is a floating 75% image window with its full button bar floating
# over it: no dim scrim, no card background, border, shadow or outer margins.
# Clicking outside still closes it. Text previews keep a framed card.
check_absent "Peek has no dimming scrim" "$PEEK_PANEL" 'colScrim'
check "Peek keeps a click-to-close backdrop" "$PEEK_PANEL" 'id: backdrop'
check "Peek has an image mode flag" "$PEEK_PANEL" 'readonly property bool imageMode: Peek.kind === "image"'
check "Peek card is transparent for images" "$PEEK_PANEL" 'color: imageMode ? "transparent" : Appearance.colors.colUiPopupBackground'
check "Peek card has no border for images" "$PEEK_PANEL" 'border.width: imageMode ? 0 : 1'
check "Peek card has no shadow for images" "$PEEK_PANEL" 'StyledRectangularShadow { target: card; visible: !imageMode }'
check "Peek body has no margins for images" "$PEEK_PANEL" 'anchors.margins: imageMode ? 0 : 10'
check "Peek body starts at the top for images" "$PEEK_PANEL" 'anchors.topMargin: imageMode ? 0 : 50'
check "Peek body is transparent for images" "$PEEK_PANEL" 'color: imageMode ? "transparent" : Appearance.colors.colLayer1'
check "Peek header floats over the image" "$PEEK_PANEL" 'z: 2'
check "Peek header has a translucent background" "$PEEK_PANEL" 'opacity: 0.8'
check "Peek header stays visible" "$PEEK_PANEL" 'height: 32'
check "Peek has a copy-image button" "$PEEK_PANEL" 'text: "content_copy"'
check "Peek copy-image button is wired" "$PEEK_PANEL" 'Peek.copyImage()'
check "Peek has a copy-path button" "$PEEK_PANEL" 'text: "link"'
check "Peek copy-path button is wired" "$PEEK_PANEL" 'Peek.copyPath()'
check "Peek shows copy feedback in the header" "$PEEK_PANEL" 'Peek.actionMessage'

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
