#!/usr/bin/env bash
# Regression test: the startup gate must wait for org.bluez but never block
# login when Bluetooth is absent or bluetoothd is slow to start.
#
# Run:  bash tests/test_wait_for_bluez.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAIT_SCRIPT="$SCRIPT_DIR/scripts/bluetooth/wait-for-bluez.sh"

fail=0
check() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL: %s: expected %q, got %q\n' "$label" "$expected" "$actual" >&2
        fail=1
    else
        printf '  OK   %s = %s\n' "$label" "$actual"
    fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_stub() {
    cat > "$tmp/dbus-send" <<'STUB'
#!/usr/bin/env bash
printf 'call\n' >> "$STUB_LOG"
if [[ -n "${STUB_HANG:-}" ]]; then sleep 5; fi
n="$(wc -l < "$STUB_LOG")"
if [[ -n "${STUB_FAIL_FIRST_N:-}" && "$n" -le "$STUB_FAIL_FIRST_N" ]]; then
    exit 1
fi
exit 0
STUB
    chmod +x "$tmp/dbus-send"
}
make_stub

run_case() {
    local label="$1" fail_first="$2"
    : > "$tmp/stub.log"
    STUB_LOG="$tmp/stub.log" STUB_FAIL_FIRST_N="$fail_first" \
        END4PC_BT_WAIT_SECONDS=0.6 PATH="$tmp:$PATH" \
        bash "$WAIT_SCRIPT"
    local rc=$?
    printf '%s %s\n' "$rc" "$(wc -l < "$tmp/stub.log")"
}

# Case A: BlueZ already present -> one probe, immediate success.
result="$(run_case immediate 0)"
check "immediate: rc"    "$(awk '{print $1}' <<<"$result")" "0"
check "immediate: calls" "$(awk '{print $2}' <<<"$result")" "1"

# Case B: BlueZ appears on the third probe -> keep polling.
result="$(run_case delayed 2)"
check "delayed: rc"    "$(awk '{print $1}' <<<"$result")" "0"
check "delayed: calls" "$(awk '{print $2}' <<<"$result")" "3"

# Case C: BlueZ never appears -> bounded retries, still exit 0.
result="$(run_case absent 999)"
check "absent: rc" "$(awk '{print $1}' <<<"$result")" "0"
if [[ "$(awk '{print $2}' <<<"$result")" -ge 3 ]]; then
    printf '  OK   absent: bounded retries attempted\n'
else
    printf 'FAIL: absent: expected at least 3 probes, got %s\n' \
        "$(awk '{print $2}' <<<"$result")" >&2
    fail=1
fi

# Case D: a hung D-Bus probe must not block login past the gate's own bound.
: > "$tmp/stub.log"
start="$(date +%s)"
STUB_LOG="$tmp/stub.log" STUB_HANG=1 END4PC_BT_WAIT_SECONDS=0.6 \
    PATH="$tmp:$PATH" timeout 3 bash "$WAIT_SCRIPT"
rc=$?
elapsed="$(( $(date +%s) - start ))"
check "hung probe: rc" "$rc" "0"
if [[ "$elapsed" -lt 3 ]]; then
    printf '  OK   hung probe: exited in %ss\n' "$elapsed"
else
    printf 'FAIL: hung probe: took %ss (must be < 3s)\n' "$elapsed" >&2
    fail=1
fi

exit "$fail"
