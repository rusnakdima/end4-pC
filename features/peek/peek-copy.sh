#!/usr/bin/env bash
# Copy a Peek target to the Wayland clipboard.
#
#   peek-copy.sh image <path>   copy the image pixels as image/png
#   peek-copy.sh path  <path>   copy the path as plain text
set -u

mode="${1:-}"
path="${2:-}"

usage() {
    printf 'usage: peek-copy.sh image|path <path>\n' >&2
    exit 2
}

case "$mode" in
    path)
        [ -n "$path" ] || usage
        printf '%s' "$path" | wl-copy
        ;;
    image)
        if [ -z "$path" ] || [ ! -f "$path" ] || [ ! -r "$path" ]; then
            printf 'not a readable file: %s\n' "$path" >&2
            exit 1
        fi
        case "$path" in
            *.png|*.PNG)
                cat -- "$path" | wl-copy -t image/png
                ;;
            *)
                if [ "${PEEK_NO_MAGICK:-0}" != "1" ] && command -v magick >/dev/null 2>&1; then
                    magick "$path" png:- | wl-copy -t image/png
                elif command -v convert >/dev/null 2>&1; then
                    convert "$path" png:- | wl-copy -t image/png
                elif command -v ffmpeg >/dev/null 2>&1; then
                    ffmpeg -v error -i "$path" -f image2pipe -vcodec png - | wl-copy -t image/png
                else
                    printf 'no image converter available\n' >&2
                    exit 1
                fi
                ;;
        esac
        ;;
    *)
        usage
        ;;
esac
