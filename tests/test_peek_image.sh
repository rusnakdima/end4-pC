#!/usr/bin/env bash
# Tests for the image handoff helper: images open in swappy, not nvim.
#
# Run:  bash tests/test_peek_image.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$SCRIPT_DIR/features/peek/peek-image.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
LOG="$TMP/log"

cat > "$TMP/bin/swappy" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
    printf '[%s]\n' "$arg" >> "$PEEK_TEST_LOG"
done
STUB
chmod +x "$TMP/bin/swappy"
printf 'image bytes\n' > "$TMP/a b.png"

fail=0
check() {
    local label="$1" condition="$2"
    if [ "$condition" = "0" ]; then
        printf '  OK   %s\n' "$label"
    else
        printf 'FAIL: %s\n' "$label" >&2
        fail=1
    fi
}

# Valid image: swappy gets -f and the path as one argument.
PEEK_SWAPPY="$TMP/bin/swappy" PEEK_TEST_LOG="$LOG" "$HELPER" "$TMP/a b.png" >"$TMP/out" 2>"$TMP/err"
check "valid image exits 0" "$?"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$LOG" ] && break
    sleep 0.1
done
grep -Fxq -- '[-f]' "$LOG"; check "swappy receives -f" "$?"
grep -Fxq -- "[$TMP/a b.png]" "$LOG"; check "path with spaces is one argument" "$?"
[ "$(wc -l < "$LOG")" -eq 2 ]; check "swappy receives exactly two arguments" "$?"
[ ! -s "$TMP/err" ]; check "no stderr on success" "$?"

# Missing file: fail before touching swappy.
LOG2="$TMP/log2"
PEEK_SWAPPY="$TMP/bin/swappy" PEEK_TEST_LOG="$LOG2" "$HELPER" "$TMP/missing.png" >"$TMP/out2" 2>"$TMP/err2"
[ "$?" -ne 0 ]; check "missing image exits non-zero" "$?"
grep -Fq 'not a readable file' "$TMP/err2"; check "missing image reports a clear error" "$?"
[ ! -e "$LOG2" ]; check "missing image does not launch swappy" "$?"

# swappy absent: clear error, no silent success.
LOG3="$TMP/log3"
PEEK_SWAPPY="$TMP/no-such-swappy" PEEK_TEST_LOG="$LOG3" "$HELPER" "$TMP/a b.png" >"$TMP/out3" 2>"$TMP/err3"
[ "$?" -ne 0 ]; check "missing swappy exits non-zero" "$?"
grep -Fq 'swappy not installed' "$TMP/err3"; check "missing swappy reports a clear error" "$?"
[ ! -e "$LOG3" ]; check "missing swappy does not launch anything" "$?"

if [ "$fail" -ne 0 ]; then
    printf 'FAILED\n' >&2
    exit 1
fi
printf 'Peek image checks passed\n'
