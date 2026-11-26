#!/usr/bin/env bash
# Peek image handoff: open an image in swappy without blocking the caller.
# Text and other files go through peek-edit.sh (nvim) instead.
set -u

path="${1:-}"
if [ -z "$path" ] || [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf 'peek-image: not a readable file: %s\n' "$path" >&2
    exit 1
fi

viewer="${PEEK_SWAPPY:-swappy}"
if ! command -v "$viewer" >/dev/null 2>&1; then
    printf 'peek-image: swappy not installed: %s\n' "$viewer" >&2
    exit 1
fi

if command -v setsid >/dev/null 2>&1; then
    setsid "$viewer" -f "$path" </dev/null >/dev/null 2>&1 &
else
    "$viewer" -f "$path" </dev/null >/dev/null 2>&1 &
fi

exit 0
