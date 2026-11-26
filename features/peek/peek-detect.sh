#!/usr/bin/env bash
# Peek target detection: resolve PRIMARY selection or clipboard into one line:
#   KIND<TAB>PATH<TAB>LABEL
# KIND is `path` (PATH is a readable file) or `empty` (PATH is `-`).
# Run with PEEK_CACHE_DIR set; set PEEK_NO_PRIMARY=1 for wl-paste backends that
# cannot serve PRIMARY without hanging.
set -u

cache="${PEEK_CACHE_DIR:-}"
[ -n "$cache" ] || { printf 'PEEK_CACHE_DIR is required\n' >&2; exit 1; }
mkdir -p "$cache"

emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; exit 0; }

text_probe="$cache/.peek-text-$$"
trap 'rm -f "$text_probe"' EXIT

probe_image() {
    local dest="$1"
    shift
    : > "$dest"
    timeout 2 wl-paste "$@" -t image/png > "$dest" 2>/dev/null || true
    if [ -s "$dest" ]; then
        return 0
    fi
    rm -f "$dest"
    return 1
}

probe_text() {
    : > "$text_probe"
    timeout 2 wl-paste "$@" -n > "$text_probe" 2>/dev/null || true
    [ -s "$text_probe" ]
}

resolve_text() {
    local label="$1" raw trimmed
    raw="$(cat "$text_probe")"
    trimmed="${raw#"${raw%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    case "$trimmed" in
        "~"|"~/"*) trimmed="$HOME/${trimmed#\~/}" ;;
    esac
    trimmed="${trimmed#file://}"
    if [[ "$trimmed" = /* && -e "$trimmed" ]]; then
        emit path "$trimmed" "$(basename -- "$trimmed")"
    fi
    if [ -z "$trimmed" ]; then
        return 1
    fi
    local scratch="$cache/selection-$(date +%s).txt"
    cp "$text_probe" "$scratch"
    emit path "$scratch" "$label"
}

if [ "${PEEK_NO_PRIMARY:-0}" != 1 ]; then
    if probe_image "$cache/primary.png" -p; then
        emit path "$cache/primary.png" "Primary selection (image)"
    fi
    if probe_text -p && resolve_text "Selected text"; then
        :
    fi
fi

if probe_image "$cache/clipboard.png"; then
    emit path "$cache/clipboard.png" "Clipboard image"
fi
if probe_text && resolve_text "Clipboard text"; then
    :
fi

emit empty - "Nothing selected"
