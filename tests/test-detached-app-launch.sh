#!/usr/bin/env bash
#
# Contract test: GUI apps launched by theme-owned code must be detached from
# Quickshell. A tracked Process is killed by Quickshell.reload(true) (theme
# reload), which closes the app window along with it. execDetached() and
# Process.startDetached() are documented to survive a reload.
#
# Covers the three launch paths that own a long-lived GUI:
#   * GeneratedCommandShortcuts.runCommand() - all generated command keybinds
#     (YTM/CTRL+SUPER+M, terminal, browser, pavucontrol, custom commands, ...)
#   * Webapps.open() - webapp windows opened from the settings/dashboard
#   * Waydroid.openFullUI() - the Waydroid full-UI window
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

GEN="$ROOT/services/GeneratedCommandShortcuts.qml"
WEB="$ROOT/services/Webapps.qml"
WAY="$ROOT/services/Waydroid.qml"

for file in "$GEN" "$WEB" "$WAY"; do
    [[ -f "$file" ]] || fail "missing $file"
done

body_of() {
    awk -v name="function $2(" '
        index($0, name) { found = 1 }
        found { print }
        found && /^    \}/ { exit }
    ' "$1"
}

# 1. Generated command keybinds: detached, no tracked runner Process.
run_body="$(body_of "$GEN" runCommand)"
[[ -n "$run_body" ]] || fail 'runCommand() not found'
grep -q 'Quickshell.execDetached' <<<"$run_body" ||
    fail 'runCommand() does not launch the command detached'
if grep -q 'runnerComponent\|running: true' <<<"$run_body"; then
    fail 'runCommand() still starts a tracked Process'
fi
if grep -q 'runnerComponent' "$GEN"; then
    fail 'the self-destroying runnerComponent Process is still declared'
fi

# 2. Webapps: opening a webapp window must be detached too.
open_body="$(body_of "$WEB" open)"
[[ -n "$open_body" ]] || fail 'Webapps.open() not found'
grep -q 'Quickshell.execDetached' <<<"$open_body" ||
    fail 'Webapps.open() does not launch the webapp detached'
if grep -q 'openProc' <<<"$open_body"; then
    fail 'Webapps.open() still uses the tracked openProc'
fi
if grep -q 'id: openProc' "$WEB"; then
    fail 'the openProc Process is still declared'
fi

# 3. Waydroid full UI: detached, while keeping the timeout-bound command that
#    the session/action contract pins.
ui_body="$(body_of "$WAY" openFullUI)"
[[ -n "$ui_body" ]] || fail 'Waydroid.openFullUI() not found'
grep -qE 'startDetached\(\)|Quickshell\.execDetached' <<<"$ui_body" ||
    fail 'Waydroid.openFullUI() does not launch the UI detached'
if grep -q 'uiProc\.running = true' "$WAY"; then
    fail 'Waydroid still opens the UI through a tracked Process'
fi
grep -q 'command: \["timeout", "30", "waydroid", "show-full-ui"\]' "$WAY" ||
    fail 'the timeout-bound full-UI command was removed'

echo 'PASS: app launches are detached from the theme'
