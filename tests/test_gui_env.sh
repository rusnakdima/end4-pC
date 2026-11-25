#!/usr/bin/env bash
# Regression test for scripts/gui-env.sh: X11 viewers must get a DISPLAY
# even when the invoking shell did not inherit one.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0

# 1. No DISPLAY in the environment -> helper must supply one.
out=$(env -u DISPLAY -u XAUTHORITY bash -c \
    'source scripts/gui-env.sh >/dev/null 2>&1; printf "%s" "${DISPLAY:-}"')
if [[ ! "$out" =~ ^:[0-9]+$ ]]; then
    echo "FAIL: expected a :<number> DISPLAY fallback, got '${out}'" >&2
    fail=1
else
    echo "PASS: DISPLAY fallback = $out"
fi

# 2. An existing DISPLAY must be left untouched.
out=$(env DISPLAY=:7 bash -c \
    'source scripts/gui-env.sh >/dev/null 2>&1; printf "%s" "${DISPLAY:-}"')
if [[ "$out" != ":7" ]]; then
    echo "FAIL: existing DISPLAY was overwritten: '$out'" >&2
    fail=1
else
    echo "PASS: existing DISPLAY preserved"
fi

exit "$fail"
