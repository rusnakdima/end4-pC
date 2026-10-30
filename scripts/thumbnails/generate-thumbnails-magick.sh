#!/usr/bin/env bash

# Generate thumbnails for files using ImageMagick, following Freedesktop spec
# Usage:
#   ./generate-thumbnails-magick.sh --file <path>
#   ./generate-thumbnails-magick.sh --directory <path>

set -e

# Thumbnail sizes mapping
get_thumbnail_size() {
    case "$1" in
        normal) echo 128 ;;
        large) echo 256 ;;
        x-large) echo 512 ;;
        xx-large) echo 1024 ;;
        *) echo 128 ;;
    esac
}

usage() {
    echo "Usage: $0 --file <path> | --directory <path>"
    exit 1
}

md5() {
    # Calculate md5 hash of the file's absolute path
    echo -n "$1" | md5sum | awk '{print $1}'
}

urlencode() {
    # Percent-encode a string for use in a URI, but do not encode slashes
    local str="$1"
    local encoded=""
    local c
    for ((i=0; i<${#str}; i++)); do
        c="${str:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]|/|'('|')'|'*') encoded+="$c" ;;
            *) printf -v hex '%%%02X' "'${c}'"; encoded+="$hex" ;;
        esac
    done
    echo "$encoded"
}

generate_thumbnail() {
    local src="$1"
    local abs_path
    abs_path="$(realpath "$src")"
    local encoded_path
    encoded_path="$(urlencode "$abs_path")"
    local uri
    uri="file://$encoded_path"
    local hash
    hash="$(md5 "$uri")"
    local out="$CACHE_DIR/$hash.png"
    mkdir -p "$CACHE_DIR"
    # A cached thumbnail that is older than the file itself is stale and gets
    # rendered again.
    if [ -f "$out" ] && [ "$out" -nt "$abs_path" ]; then
        return
    fi
    # Videos get a poster frame, everything else is rendered by ImageMagick.
    case "${abs_path,,}" in
        *.mp4|*.webm|*.mkv|*.avi|*.mov|*.m4v|*.wmv|*.flv|*.ogv|*.3gp|*.qt)
            # The first frame of a clip is usually black (fade in), so a frame
            # a few seconds in is used.
            rendered=0
            for seek in 00:00:03 00:00:01 00:00:00; do
                if ffmpeg -y -ss "$seek" -i "$abs_path" -frames:v 1 \
                    -vf "scale=${THUMBNAIL_SIZE}:${THUMBNAIL_SIZE}:force_original_aspect_ratio=decrease" \
                    -f image2 "$out" >/dev/null 2>&1; then
                    rendered=1
                    break
                fi
                rm -f "$out"
            done
            if [ "$rendered" -eq 0 ]; then
                # A flat placeholder, so the preview is never an empty cell.
                magick -size "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "xc:#202020" "$out" >/dev/null 2>&1 || rm -f "$out"
            fi
            ;;
        *)
            magick "$abs_path" -auto-orient -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "$out"
            ;;
    esac
}

# Parse arguments
SIZE_NAME="normal"
MODE=""
TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file|-f)
            MODE="file"
            TARGET="$2"
            shift 2
            ;;
        --directory|-d)
            MODE="dir"
            TARGET="$2"
            shift 2
            ;;
        --size|-s)
            SIZE_NAME="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
    # Only one mode allowed
    [[ -n "$MODE" ]] && break
done

THUMBNAIL_SIZE="$(get_thumbnail_size "$SIZE_NAME")"
# The shell reads the cache through StandardPaths.GenericCacheLocation, so the
# same root has to be used here.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails/$SIZE_NAME"

if [ -z "$MODE" ] || [ -z "$TARGET" ]; then
    usage
fi

case "$MODE" in
    file)
        if [ ! -f "$TARGET" ]; then
            echo "File not found: $TARGET"
            exit 2
        fi
        generate_thumbnail "$TARGET"
        ;;
    dir)
        if [ ! -d "$TARGET" ]; then
            echo "Directory not found: $TARGET"
            exit 2
        fi
        # Only files that can actually be rendered are processed, so the
        # progress count matches the number of real thumbnails.
        files=()
        for f in "$TARGET"/*; do
            [ -f "$f" ] || continue
            case "${f,,}" in
                *.png|*.jpg|*.jpeg|*.webp|*.bmp|*.gif|*.tif|*.tiff|*.avif|*.jxl|*.heic|*.heif) ;;
                *.mp4|*.webm|*.mkv|*.avi|*.mov|*.m4v|*.wmv|*.flv|*.ogv|*.3gp|*.qt) ;;
                *) continue ;;
            esac
            files+=("$f")
        done
        total=${#files[@]}
        [ "$total" -eq 0 ] && exit 0
        counter_file="$(mktemp)"
        echo "0" > "$counter_file"
        for f in "${files[@]}"; do
            (
                generate_thumbnail "$f"
                # The progress protocol the picker listens for, so a cell
                # reloads its thumbnail as soon as it exists.
                completed=$(flock "$counter_file" sh -c 'read c < "$1"; echo $((c + 1)) > "$1"; echo $((c + 1))' _ "$counter_file")
                echo "PROGRESS $completed/$total FILE $(realpath "$f")"
            ) &
        done
        wait
        rm -f "$counter_file"
        ;;
    *)
        usage
        ;;
esac

