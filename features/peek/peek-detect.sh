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

normalize_candidate() {
    local c="$1"
    c="${c#"${c%%[![:space:]]*}"}"
    c="${c%"${c##*[![:space:]]}"}"
    case "$c" in
        \"*\") c="${c#\"}"; c="${c%\"}" ;;
        "'"*"'") c="${c#\'}"; c="${c%\'}" ;;
        \`*\`) c="${c#\`}"; c="${c%\`}" ;;
    esac
    # IDE selections often append :line or :line:column to a path.
    printf '%s' "$c" | sed -E 's/:[0-9]+(:[0-9]+)?$//; s/[,;:]+$//'
}

# Accept absolute paths, ~/ paths and file:// URIs (including percent-encoded
# ones from file managers) as the same kind of target.
decode_candidate() {
    local c="$1"
    case "$c" in
        file://*)
            c="${c#file://}"
            case "$c" in
                localhost/*) c="/${c#localhost/}" ;;
            esac
            if command -v python3 >/dev/null 2>&1; then
                c="$(python3 -c 'import sys, urllib.parse; sys.stdout.write(urllib.parse.unquote(sys.stdin.read().rstrip("\n")))' <<< "$c")"
            else
                c="$(printf '%b' "${c//%/\\x}")"
            fi
            ;;
    esac
    case "$c" in
        "~"|"~/"*) c="$HOME/${c#\~/}" ;;
    esac
    normalize_candidate "$c"
}

candidate_is_path() {
    [[ "$1" = /* && -f "$1" && -r "$1" ]]
}

# Fills RESULT_IS_PATH, RESULT_PATH, RESULT_LABEL and RESULT_HAS_TEXT from the
# current text probe. A real path anywhere in the selection beats plain text.
resolve_text() {
    local label="$1" raw trimmed line candidate
    RESULT_IS_PATH=0
    RESULT_PATH=""
    RESULT_LABEL=""
    RESULT_HAS_TEXT=0
    raw="$(cat "$text_probe")"
    trimmed="${raw#"${raw%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [ -n "$trimmed" ] || return 0
    RESULT_HAS_TEXT=1
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        candidate="$(decode_candidate "$line")"
        if candidate_is_path "$candidate"; then
            RESULT_IS_PATH=1
            RESULT_PATH="$candidate"
            RESULT_LABEL="$(basename -- "$candidate")"
            return 0
        fi
    done <<< "$trimmed"
    RESULT_PATH="$cache/selection-$(date +%s)-$$-$RANDOM.txt"
    cp "$text_probe" "$RESULT_PATH"
    RESULT_LABEL="$label"
}

# Examine both selections before deciding: PRIMARY may hold stale plain text
# while an explicit copy put a file URI on the clipboard.
primary_is_path=0 primary_path="" primary_label="" primary_has_text=0
clipboard_is_path=0 clipboard_path="" clipboard_label="" clipboard_has_text=0

if [ "${PEEK_NO_PRIMARY:-0}" != 1 ]; then
    if probe_image "$cache/primary.png" -p; then
        emit path "$cache/primary.png" "Primary selection (image)"
    fi
    if probe_text -p; then
        resolve_text "Selected text"
        primary_is_path="$RESULT_IS_PATH"
        primary_path="$RESULT_PATH"
        primary_label="$RESULT_LABEL"
        primary_has_text="$RESULT_HAS_TEXT"
    fi
fi

if probe_image "$cache/clipboard.png"; then
    emit path "$cache/clipboard.png" "Clipboard image"
fi
if probe_text; then
    resolve_text "Clipboard text"
    clipboard_is_path="$RESULT_IS_PATH"
    clipboard_path="$RESULT_PATH"
    clipboard_label="$RESULT_LABEL"
    clipboard_has_text="$RESULT_HAS_TEXT"
fi

# An explicit copy is a stronger signal than a stale PRIMARY selection.
if [ "$clipboard_is_path" = 1 ]; then
    emit path "$clipboard_path" "$clipboard_label"
fi
if [ "$primary_is_path" = 1 ]; then
    emit path "$primary_path" "$primary_label"
fi
if [ "$clipboard_has_text" = 1 ]; then
    emit path "$clipboard_path" "$clipboard_label"
fi
if [ "$primary_has_text" = 1 ]; then
    emit path "$primary_path" "$primary_label"
fi

emit empty - "Nothing selected"
