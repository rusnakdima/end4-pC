#!/usr/bin/env bash
#
# applycolor.sh must never signal kitty processes. SIGUSR1 makes kitty reload
# its whole config and can close windows; theming should use the remote-control
# colour API and skip instances that do not expose it.
#
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state/user/generated/terminal" "$tmp/scripts/terminal"

cat > "$tmp/bin/pgrep" <<'EOF'
#!/bin/sh
echo 424242
EOF

cat > "$tmp/bin/kitten" <<'EOF'
#!/bin/sh
echo "$*" >> "$KITTEN_LOG"
[ "${KITTEN_FAIL:-0}" = 1 ] && exit 1
exit 0
EOF

cat > "$tmp/bin/kill" <<'EOF'
#!/bin/sh
echo "$*" >> "$KILL_LOG"
exit 0
EOF
chmod +x "$tmp/bin/pgrep" "$tmp/bin/kitten" "$tmp/bin/kill"

printf '# theme template\n' > "$tmp/scripts/terminal/kitty-theme.conf"

sed -n '/^apply_kitty() {/,/^}/p' "$root/scripts/colors/applycolor.sh" > "$tmp/apply_kitty.sh"
if [[ ! -s "$tmp/apply_kitty.sh" ]]; then
    echo "FAIL: could not extract apply_kitty() from applycolor.sh" >&2
    exit 1
fi

passed=0
failed=0
expect() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "ok   $label"
        passed=$((passed + 1))
    else
        echo "FAIL $label: expected '$expected', got '$actual'"
        failed=$((failed + 1))
    fi
}

run_kitty_theme() {
    local fail="$1" log="$2" kitten_log
    kitten_log="$tmp/kitten-$fail.log"
    : > "$log"
    : > "$kitten_log"
    if ! STATE_DIR="$tmp/state" SCRIPT_DIR="$tmp/scripts" \
        KILL_LOG="$log" KITTEN_LOG="$kitten_log" KITTEN_FAIL="$fail" \
        PATH="$tmp/bin:$PATH" \
        bash -c '
            kill() { echo "$*" >> "$KILL_LOG"; }
            source "$1"
            colorlist=()
            colorvalues=()
            apply_kitty
        ' _ "$tmp/apply_kitty.sh"; then
        echo "FAIL apply_kitty execution (fail=$fail)" >&2
        failed=$((failed + 1))
    fi
}

run_kitty_theme 1 "$tmp/kill-fallback.log"
expect "no kill when remote control is unavailable" "" \
    "$(cat "$tmp/kill-fallback.log" 2>/dev/null || true)"
expect "remote-control set-colors attempted (fail case)" 1 \
    "$(grep -c 'set-colors --all --configured' "$tmp/kitten-1.log")"

run_kitty_theme 0 "$tmp/kill-remote.log"
expect "no kill when remote control succeeds" "" \
    "$(cat "$tmp/kill-remote.log" 2>/dev/null || true)"
expect "remote-control set-colors attempted (success case)" 1 \
    "$(grep -c 'set-colors --all --configured' "$tmp/kitten-0.log")"

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
