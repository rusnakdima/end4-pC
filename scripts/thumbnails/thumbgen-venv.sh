#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure HOME points to the actual user's home for thumbnail cache and path expansion
# When run via sudo -u, HOME may still be the original user's home - fix it
export HOME="$(getent passwd "$(whoami)" | cut -d: -f6)"

VENV_DIR="$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV" 2>/dev/null)"
if [[ -n "$VENV_DIR" && -f "$VENV_DIR/bin/activate" ]]; then
    source "$VENV_DIR/bin/activate"
    GIO_USE_VFS=local python3 "$SCRIPT_DIR/thumbgen.py" "$@"
    THUMBGEN_EXIT_CODE=$?
    deactivate
else
    # Fallback to system Python if venv is missing or broken
    GIO_USE_VFS=local python3 "$SCRIPT_DIR/thumbgen.py" "$@"
    THUMBGEN_EXIT_CODE=$?
fi

exit $THUMBGEN_EXIT_CODE
