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
    local fail="$1" log="$2"
    STATE_DIR="$tmp/state" SCRIPT_DIR="$tmp/scripts" \
    KILL_LOG="$log" KITTEN_FAIL="$fail" PATH="$tmp/bin:$PATH" \
        bash -c '
            kill() { echo "$*" >> "$KILL_LOG"; }
            source "$1"
            colorlist=()
            colorvalues=()
            apply_kitty
        ' _ "$tmp/apply_kitty.sh"
}

run_kitty_theme 1 "$tmp/kill-fallback.log"
expect "no kill when remote control is unavailable" "" \
    "$(cat "$tmp/kill-fallback.log" 2>/dev/null || true)"

run_kitty_theme 0 "$tmp/kill-remote.log"
expect "no kill when remote control succeeds" "" \
    "$(cat "$tmp/kill-remote.log" 2>/dev/null || true)"

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
