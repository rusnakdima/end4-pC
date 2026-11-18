#!/usr/bin/env bash
#
# Runs the QML unit tests inside a live Quickshell.
#
# The services of this config can only be loaded inside a Quickshell
# process: qmltestrunner cannot resolve "import Quickshell", so every
# service is untestable under it. The tests therefore run in a hosted
# harness, tests/shell-tests/shell.qml, which prints a summary line:
#
#   SHELL_TEST_RESULT passed=<n> failed=<n> skipped=<n> total=<n>
#
# The exit code of the run is decided here and not by the shell: the
# summary line must be present and failed must be 0. A shell that exits
# without printing the line is a failure, never a pass.
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

HARNESS_DIR="tests/shell-tests"
TIMEOUT_SECONDS="${SHELL_TEST_TIMEOUT_SECONDS:-120}"

if ! command -v qs > /dev/null 2>&1; then
    echo "quickshell not found: the hosted tests need the 'qs' binary on PATH" >&2
    exit 2
fi

# The harness creates no window, but Quickshell itself still needs a
# Wayland display to start, and a runtime directory for its sockets. A variable
# that is *set* to a stale path (common inside containers and sudo sessions)
# used to crash the shell instead of failing this script with a clear message.
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ ! -d "$runtime_dir" ]]; then
    fallback="/run/user/$(id -u)"
    if [[ -d "$fallback" ]]; then
        echo "XDG_RUNTIME_DIR='$runtime_dir' is not a directory; using '$fallback'" >&2
        runtime_dir="$fallback"
    else
        echo "XDG_RUNTIME_DIR is invalid and $fallback does not exist" >&2
        exit 2
    fi
fi
export XDG_RUNTIME_DIR="$runtime_dir"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    # Pick up the socket of a running session, if there is one.
    for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        [[ -S "$socket" ]] || continue
        export WAYLAND_DISPLAY="${socket##*/}"
        break
    done
fi

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "no Wayland display found: set WAYLAND_DISPLAY or start a session" >&2
    exit 2
fi

# Qt's default "wayland;xcb" combination can pick the wrong plugin in a
# headless harness, which makes the shell exit before printing any results.
export QT_QPA_PLATFORM=wayland

output=$(mktemp)
trap 'rm -f "$output"' EXIT

qs -p "$HARNESS_DIR" > "$output" 2>&1 &
shell_pid=$!

# Give the shell its time, then take it down.
( sleep "$TIMEOUT_SECONDS"; kill -TERM "$shell_pid" 2> /dev/null ) &
watchdog_pid=$!

set +e
wait "$shell_pid"
shell_status=$?
kill "$watchdog_pid" 2> /dev/null
set -e

result_line=$(grep -E '^.*SHELL_TEST_RESULT ' "$output" | tail -n 1 || true)

if [[ -z "$result_line" ]]; then
    echo "FAIL: the shell exited without a result line after ${TIMEOUT_SECONDS}s (status $shell_status)" >&2
    echo "A test file may be hanging; the files below never reported." >&2
    echo "--- output ---" >&2
    cat "$output" >&2
    echo "--- files that did not report ---" >&2
    grep -oE '^.*TESTFILE [^ ]+' "$output" | awk '{print $NF}' | sort -u > "$output.reported" || true
    for file in "$HARNESS_DIR"/tst_*.qml; do
        name="${file##*/}"
        if ! grep -qxF "$name" "$output.reported" 2> /dev/null; then
            echo "  $name" >&2
        fi
    done
    rm -f "$output.reported"
    exit 1
fi

# The per file summary, so a failure points at a file.
echo "== hosted shell tests =="
while IFS= read -r line; do
    echo "  ${line#*TESTFILE }"
done < <(grep -E '^.*TESTFILE ' "$output" || true)

summary=${result_line##*SHELL_TEST_RESULT }
echo "SHELL_TEST_RESULT $summary"

failed=$(sed -nE 's/.*failed=([0-9]+).*/\1/p' <<< "$summary")
if [[ -z "$failed" ]]; then
    echo "FAIL: the result line has no failed count" >&2
    exit 1
fi

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

exit 0
