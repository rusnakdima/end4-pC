#!/usr/bin/env bash
set -euo pipefail

# Resolve the shell's python venv and run the whisper STT script with it.
# Order: $ILLOGICAL_IMPULSE_VIRTUAL_ENV -> $XDG_STATE_HOME/quickshell/.venv
#        -> $HOME/.local/state/quickshell/.venv

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/stt.py"

if [[ -n "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-}" ]]; then
    venv="$ILLOGICAL_IMPULSE_VIRTUAL_ENV"
elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
    venv="$XDG_STATE_HOME/quickshell/.venv"
else
    venv="$HOME/.local/state/quickshell/.venv"
fi

if [[ ! -x "$venv/bin/python" ]]; then
    echo "stt: python venv not found at $venv - install it with install.sh" >&2
    printf '{"error": "python venv not found at %s - install it with install.sh"}\n' "$venv"
    exit 2
fi

exec "$venv/bin/python" "$script" "$@"
