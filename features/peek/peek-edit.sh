#!/usr/bin/env bash
# Peek editor handoff: open a file in nvim (LazyVim) in a real terminal with a
# unique window title, without blocking the caller.
set -u

path="${1:-}"
if [ -z "$path" ] || [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf 'peek-edit: not a readable file: %s\n' "$path" >&2
    exit 1
fi

title="${PEEK_TITLE:-end4-pc-peek}"
editor="${PEEK_NVIM:-nvim}"
terminal="${PEEK_TERMINAL:-}"

if [ -n "$terminal" ]; then
    if ! command -v "$terminal" >/dev/null 2>&1; then
        printf 'peek-edit: no terminal emulator: %s\n' "$terminal" >&2
        exit 1
    fi
else
    for candidate in foot kitty alacritty konsole xterm; do
        if command -v "$candidate" >/dev/null 2>&1; then
            terminal="$candidate"
            break
        fi
    done
    if [ -z "$terminal" ]; then
        printf 'peek-edit: no terminal emulator found (set PEEK_TERMINAL)\n' >&2
        exit 1
    fi
fi

case "$terminal" in
    foot|kitty)
        argv=("$terminal" "--title=$title" "$editor" -- "$path")
        ;;
    alacritty)
        argv=("$terminal" --title "$title" --command "$editor" -- "$path")
        ;;
    konsole)
        argv=("$terminal" --new-window --title "$title" -e "$editor" "$path")
        ;;
    xterm)
        argv=("$terminal" -title "$title" -e "$editor" "$path")
        ;;
    *)
        argv=("$terminal" "--title=$title" "$editor" -- "$path")
        ;;
esac

if command -v setsid >/dev/null 2>&1; then
    setsid "${argv[@]}" </dev/null >/dev/null 2>&1 &
else
    "${argv[@]}" </dev/null >/dev/null 2>&1 &
fi

exit 0
