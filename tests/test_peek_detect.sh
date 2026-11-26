#!/usr/bin/env bash
# Regression tests for features/peek/peek-detect.sh: PRIMARY/clipboard probing,
# path normalization and the empty-selection fallback.
#
# Run:  bash tests/test_peek_detect.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$SCRIPT_DIR/features/peek/peek-detect.sh"

fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" "/tmp/peek dir" "/tmp/x y.txt"' EXIT

mkdir -p "$tmp/bin" "$tmp/cache" "/tmp/peek dir"
touch "/tmp/peek dir/a b.png"
printf 'uri target\n' > "/tmp/x y.txt"

# A wl-paste stub whose answers are chosen by STUB_WL_PASTE_MODE.
cat > "$tmp/bin/wl-paste" <<'STUB'
#!/usr/bin/env bash
args="$*"
case "${STUB_WL_PASTE_MODE:-none}" in
    primary-text-path)
        case "$args" in
            "-p -n") printf '%s' "${STUB_WL_PASTE_TEXT:-}" ;;
        esac
        ;;
    primary-text|primary-uri)
        case "$args" in
            "-p -n") printf '%s\n' "${STUB_WL_PASTE_TEXT:-}" ;;
        esac
        ;;
    primary-image)
        case "$args" in
            "-p -t image/png") printf '\211PNG\r\n\032\nstub-image' ;;
        esac
        ;;
    clipboard-image)
        case "$args" in
            "-t image/png") printf '\211PNG\r\n\032\nstub-image' ;;
        esac
        ;;
esac
STUB
chmod +x "$tmp/bin/wl-paste"
export PATH="$tmp/bin:$PATH"
export PEEK_CACHE_DIR="$tmp/cache"

ok()   { printf '  OK   %s\n' "$1"; }
bad()  { printf 'FAIL: %s (%s)\n' "$1" "$2" >&2; fail=1; }

run_detect() {
    STUB_WL_PASTE_MODE="$1" STUB_WL_PASTE_TEXT="${2:-}" \
        bash "$DETECT" 2>"$tmp/stderr"
}

expect_line() {
    local label="$1" mode="$2" text="$3" field="$4" want="$5" got
    got="$(run_detect "$mode" "$text")"
    got="$(printf '%s' "$got" | cut -f"$field")"
    if [ "$got" = "$want" ]; then ok "$label"; else bad "$label" "field $field: got <$got>, want <$want>"; fi
}

expect_suffix() {
    local label="$1" mode="$2" text="$3" field="$4" want="$5" got
    got="$(run_detect "$mode" "$text")"
    got="$(printf '%s' "$got" | cut -f"$field")"
    case "$got" in
        *"$want") ok "$label" ;;
        *) bad "$label" "field $field: got <$got>, does not end with <$want>" ;;
    esac
}

expect_line "PRIMARY path: kind" primary-text-path "/tmp/peek dir/a b.png" 1 path
expect_line "PRIMARY path: full path with spaces preserved" primary-text-path "/tmp/peek dir/a b.png" 2 "/tmp/peek dir/a b.png"
expect_line "PRIMARY path: basename label" primary-text-path "/tmp/peek dir/a b.png" 3 "a b.png"

expect_line "file:// URI normalized" primary-uri "file:///tmp/x y.txt" 2 "/tmp/x y.txt"

encoded="$tmp/x y.txt"
printf 'encoded target\n' > "$encoded"
expect_line "encoded file:// URI normalized" primary-uri "file://$tmp/x%20y.txt" 2 "$encoded"
expect_line "encoded file:// URI label" primary-uri "file://$tmp/x%20y.txt" 3 "x y.txt"
expect_line "file://localhost URI normalized" primary-uri "file://localhost$tmp/x%20y.txt" 2 "$encoded"
expect_line "uri-list first entry wins" primary-uri "file://$tmp/x%20y.txt
file://$tmp/other.txt" 2 "$encoded"

expect_line "selected text: label" primary-text "hello world" 3 "Selected text"
expect_suffix "selected text: scratch file path" primary-text "hello world" 2 .txt
scratch="$(run_detect primary-text 'hello world' | cut -f2)"
if [ -f "$scratch" ] && [ "$(cat "$scratch")" = "hello world" ]; then
    ok "selected text: scratch file keeps the text"
else
    bad "selected text: scratch file keeps the text" "missing or wrong content in <$scratch>"
fi

expect_suffix "PRIMARY image: primary.png" primary-image "" 2 /primary.png

PEEK_NO_PRIMARY=1 expect_suffix "clipboard image: clipboard.png" clipboard-image "" 2 /clipboard.png

got="$(run_detect none "")"
if [ "$got" = "$(printf 'empty\t-\tNothing selected')" ]; then
    ok "no selection: exact empty line"
else
    bad "no selection: exact empty line" "got <$got>"
fi

exit "$fail"
