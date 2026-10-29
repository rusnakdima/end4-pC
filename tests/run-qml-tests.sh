#!/usr/bin/env bash
#
# Runs the QML unit tests headless.
#
# The tests are plain QML TestCase files. They run in two stages:
#
#   1. The qmltestrunner pass over modules/common/functions. It is fast,
#      but it cannot load "import Quickshell", so only the pure JavaScript
#      modules are reachable through it.
#
#   2. The hosted pass. Every service of this config needs a live
#      Quickshell process, so the rest of the tests run in the harness at
#      tests/shell-tests, which a real `qs` process loads.
#
# Both stages must pass. The hosted pass prints
#
#   SHELL_TEST_RESULT passed=<n> failed=<n> skipped=<n> total=<n>
#
# and tests/run-shell-tests.sh decides the exit code from that line.
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The Qt 6 runner. The qmltestrunner on PATH is Qt 5, which cannot load
# the Qt 6 QML modules this theme uses.
QMLTESTRUNNER="/usr/lib/qt6/bin/qmltestrunner"
if [[ ! -x "$QMLTESTRUNNER" ]]; then
    QMLTESTRUNNER="$(command -v qmltestrunner)"
fi

status=0
for dir in modules/common/functions; do
    echo "== $dir =="
    if ! QT_QPA_PLATFORM=offscreen "$QMLTESTRUNNER" -input "$dir"; then
        status=1
    fi
done

echo "== tests/shell-tests (hosted) =="
if ! ./tests/run-shell-tests.sh; then
    status=1
fi

exit $status
