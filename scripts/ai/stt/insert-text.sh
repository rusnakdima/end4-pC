#!/usr/bin/env bash
#
# Types a transcript into the focused window.
#
# The text arrives as $1 and is passed to wtype on stdin, so it is never
# interpreted by a shell and may contain quotes, newlines or any Unicode.
#
# wtype drives the compositor's virtual keyboard. When it is missing (or the
# compositor refuses the virtual keyboard), the text is copied and pasted with
# ydotool, the same mechanism services/Cliphist.qml uses for clipboard paste.
set -u

text=${1-}
[ -z "$text" ] && exit 0

if command -v wtype > /dev/null 2>&1; then
    if printf '%s' "$text" | wtype - 2> /dev/null; then
        exit 0
    fi
fi

if ! printf '%s' "$text" | wl-copy 2> /dev/null; then
    exit 1
fi
sleep 0.05

if command -v ydotool > /dev/null 2>&1; then
    ydotool key -d 1 29:1 47:1 47:0 29:0 2> /dev/null && exit 0
fi

exit 1
