#!/usr/bin/env bash
# Regression tests for features/peek/peek-edit.sh: argv shape per terminal,
# paths with spaces as a single argument, and clear launch errors.
#
# Run:  bash tests/test_peek_edit.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDIT="$SCRIPT_DIR/features/peek/peek-edit.sh"

fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

for term in foot kitty alacritty konsole xterm; do
    cat > "$tmp/bin/$term" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG_ONE"
printf '%s\n' "$@" >> "$STUB_LOG_ARGS"
STUB
    chmod +x "$tmp/bin/$term"
done
export PATH="$tmp/bin:$PATH"
export STUB_LOG_ONE="$tmp/one.log"

target="$tmp/a file with spaces.txt"
printf 'hello\n' > "$target"

ok()  { printf '  OK   %s\n' "$1"; }
bad() { printf 'FAIL: %s (%s)\n' "$1" "$2" >&2; fail=1; }

reset_logs() {
    : > "$STUB_LOG_ONE"
    : > "$STUB_LOG_ARGS"
}

wait_log() {
    local i
    for i in $(seq 1 40); do
        [ -s "$STUB_LOG_ARGS" ] && return 0
        sleep 0.05
    done
    return 1
}

expect_log() {
    local label="$1" file="$2" needle="$3"
    if grep -Fxq -- "$needle" "$file"; then ok "$label"; else bad "$label" "<$needle> not found as a line"; fi
}

expect_substr() {
    local label="$1" file="$2" needle="$3"
    if grep -Fq -- "$needle" "$file"; then ok "$label"; else bad "$label" "<$needle> not found"; fi
}

export STUB_LOG_ARGS="$tmp/args.log"
reset_logs
PEEK_TERMINAL=foot bash "$EDIT" "$target" >/dev/null 2>"$tmp/err" || bad "foot launch" "exit failure"
wait_log || bad "foot launch" "stub never logged"
expect_log "foot: title argument" "$STUB_LOG_ARGS" "--title=end4-pc-peek"
expect_log "foot: nvim argument" "$STUB_LOG_ARGS" "nvim"
expect_log "foot: separator argument" "$STUB_LOG_ARGS" "--"
expect_log "foot: path with spaces is one argument" "$STUB_LOG_ARGS" "$target"

reset_logs
PEEK_TERMINAL=kitty bash "$EDIT" "$target" >/dev/null 2>"$tmp/err" || bad "kitty launch" "exit failure"
wait_log || bad "kitty launch" "stub never logged"
expect_log "kitty: title argument" "$STUB_LOG_ARGS" "--title=end4-pc-peek"

reset_logs
PEEK_TERMINAL=xterm bash "$EDIT" "$target" >/dev/null 2>"$tmp/err" || bad "xterm launch" "exit failure"
wait_log || bad "xterm launch" "stub never logged"
expect_substr "xterm: title and -e" "$STUB_LOG_ONE" "-title end4-pc-peek -e"

if PEEK_TERMINAL=foot bash "$EDIT" "$tmp/does-not-exist.txt" >/dev/null 2>"$tmp/err"; then
    bad "missing file rejected" "exit 0"
elif grep -Fq "not a readable file" "$tmp/err"; then
    ok "missing file rejected with a clear error"
else
    bad "missing file rejected" "stderr: $(cat "$tmp/err")"
fi

if PEEK_TERMINAL=does-not-exist bash "$EDIT" "$target" >/dev/null 2>"$tmp/err"; then
    bad "missing terminal rejected" "exit 0"
elif grep -Fq "no terminal emulator" "$tmp/err"; then
    ok "missing terminal rejected with a clear error"
else
    bad "missing terminal rejected" "stderr: $(cat "$tmp/err")"
fi

exit "$fail"
