#!/usr/bin/env bash
#
# Runs the offline backend unit tests (tests/test_*.py).
#
# The tests fake the whisper model, CUDA and pw-record, so they need no
# microphone, GPU, network or Wayland session. They use the shell venv when it
# is available (numpy is required) and fall back to system python3.
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

python=""
if [[ -n "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-}" && -x "${ILLOGICAL_IMPULSE_VIRTUAL_ENV}/bin/python" ]]; then
    python="${ILLOGICAL_IMPULSE_VIRTUAL_ENV}/bin/python"
elif [[ -n "${XDG_STATE_HOME:-}" && -x "${XDG_STATE_HOME}/quickshell/.venv/bin/python" ]]; then
    python="${XDG_STATE_HOME}/quickshell/.venv/bin/python"
elif [[ -x "$HOME/.local/state/quickshell/.venv/bin/python" ]]; then
    python="$HOME/.local/state/quickshell/.venv/bin/python"
elif command -v python3 > /dev/null 2>&1; then
    python="$(command -v python3)"
fi

if [[ -z "$python" ]]; then
    echo "python3 not found: cannot run the backend unit tests" >&2
    exit 2
fi

exec "$python" -m unittest discover -s tests -p 'test_*.py' -v
