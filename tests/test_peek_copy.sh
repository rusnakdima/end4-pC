#!/usr/bin/env bash
# Regression tests for features/peek/peek-copy.sh: clipboard image bytes,
# converter fallback, path copying and unreadable input.
#
# Run:  bash tests/test_peek_copy.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPY="$SCRIPT_DIR/features/peek/peek-copy.sh"

fail=0
tmp="$(mktemp -d)"
BASE_PATH="$PATH"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/magickbin" "$tmp/convertbin"

printf '\211PNG\r\n\032\nstub-image' > "$tmp/a b.png"
printf 'jpeg-bytes' > "$tmp/photo.jpg"

make_wl_copy() {
    cat > "$1/wl-copy" <<STUB
#!/usr/bin/env bash
printf '%s' "\$*" > "$tmp/wlcopy.args"
cat > "$tmp/wlcopy.data"
STUB
    chmod +x "$1/wl-copy"
}
make_wl_copy "$tmp/magickbin"
make_wl_copy "$tmp/convertbin"

cat > "$tmp/magickbin/magick" <<STUB
#!/usr/bin/env bash
printf '%s' "\$*" > "$tmp/converter.args"
printf 'MAGICK:%s' "\$(basename "\$1")"
STUB
chmod +x "$tmp/magickbin/magick"

cat > "$tmp/convertbin/convert" <<STUB
#!/usr/bin/env bash
printf '%s' "\$*" > "$tmp/converter.args"
printf 'CONVERT:%s' "\$(basename "\$1")"
STUB
chmod +x "$tmp/convertbin/convert"

ok()  { printf '  OK   %s\n' "$1"; }
bad() { printf 'FAIL: %s (%s)\n' "$1" "$2" >&2; fail=1; }

reset_logs() { : > "$tmp/wlcopy.args"; : > "$tmp/wlcopy.data"; : > "$tmp/converter.args"; }

run_copy() {
    reset_logs
    PATH="$1:$BASE_PATH" bash "$COPY" "${@:2}" 2>"$tmp/stderr"
}

expect_file() {
    local label="$1" file="$2" want="$3" got
    got="$(cat "$file")"
    if [ "$got" = "$want" ]; then ok "$label"; else bad "$label" "got <$got>, want <$want>"; fi
}

# A PNG is copied straight to the clipboard as image/png bytes.
run_copy "$tmp/magickbin" image "$tmp/a b.png"
expect_file "PNG goes to wl-copy as image/png" "$tmp/wlcopy.args" "-t image/png"
expect_file "PNG bytes are preserved" "$tmp/wlcopy.data" "$(cat "$tmp/a b.png")"

# Other image formats are converted to PNG before copying.
run_copy "$tmp/magickbin" image "$tmp/photo.jpg"
expect_file "magick converts JPEG to PNG" "$tmp/converter.args" "$tmp/photo.jpg png:-"
expect_file "converted bytes reach wl-copy" "$tmp/wlcopy.data" "MAGICK:photo.jpg"
expect_file "converted image uses image/png target" "$tmp/wlcopy.args" "-t image/png"

# When magick is unavailable, convert is used instead.
PEEK_NO_MAGICK=1 run_copy "$tmp/convertbin" image "$tmp/photo.jpg"
expect_file "convert is the fallback" "$tmp/converter.args" "$tmp/photo.jpg png:-"
expect_file "converted fallback bytes reach wl-copy" "$tmp/wlcopy.data" "CONVERT:photo.jpg"

# Copy path puts the exact path on the clipboard as plain text.
run_copy "$tmp/magickbin" path "$tmp/a b.png"
expect_file "copy path has no image target" "$tmp/wlcopy.args" ""
expect_file "copy path keeps spaces" "$tmp/wlcopy.data" "$tmp/a b.png"

# Missing files fail loudly and never touch the clipboard.
if run_copy "$tmp/magickbin" image "$tmp/missing.jpg"; then
    bad "missing image exits non-zero" "exit 0"
else
    ok "missing image exits non-zero"
fi
if grep -Fq 'not a readable file' "$tmp/stderr"; then
    ok "missing image explains the error"
else
    bad "missing image explains the error" "stderr: $(cat "$tmp/stderr")"
fi
if [ -s "$tmp/wlcopy.args" ] || [ -s "$tmp/wlcopy.data" ]; then
    bad "missing image does not copy" "clipboard was touched"
else
    ok "missing image does not copy"
fi

[ "$fail" -eq 0 ] || exit 1
printf 'Peek copy checks passed\n'
