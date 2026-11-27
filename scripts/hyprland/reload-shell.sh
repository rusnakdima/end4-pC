#!/usr/bin/env bash
# Reload the running quickshell theme through its own IPC bridge.
#
# Quickshell hot-reloads on QML file changes, but a deploy must not rely on
# that: the reload has to be explicit and it must never kill the shell (the
# lock surface lives in it -- see docs/superpowers/specs/2026-11-26-pip-lmb-and-
# reload-design.md). The only exception is starting a shell when none is
# running at all.
set -uo pipefail

PROG=${0##*/}
usage() {
    cat <<'EOF'
Usage: reload-shell.sh [OPTIONS]

Ask the running end4-pC quickshell instance to reload its theme. Unsafe when
the session is locked, so the lock state is checked first. No processes are
killed; a new shell is only started when no instance is running.

Options:
  -h, --help   Show this help and exit.

Environment:
  END4PC_TARGET_USER   User owning the session (default: SUDO_USER or caller).
  END4PC_TARGET_HOME   That user's home (default: looked up via getent).
  WAYLAND_DISPLAY      Override display detection.
  XDG_RUNTIME_DIR      Override runtime dir detection.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "$PROG: unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

target_user="${END4PC_TARGET_USER:-${SUDO_USER:-$(id -un)}}"
target_home="${END4PC_TARGET_HOME:-}"
[[ -n "$target_home" ]] || target_home="$(getent passwd "$target_user" | cut -d: -f6)"
runtime_dir="${XDG_RUNTIME_DIR:-}"
if [[ -z "$runtime_dir" || ! -d "$runtime_dir" ]]; then
    runtime_dir="/run/user/$(id -u "$target_user" 2>/dev/null || echo 0)"
fi

# Discover the display from the target user's runtime dir instead of assuming
# wayland-1: installers are frequently run from a TTY or over ssh.
display="${WAYLAND_DISPLAY:-}"
if [[ -z "$display" ]]; then
    best=""
    for sock in "$runtime_dir"/wayland-*; do
        [[ -S "$sock" ]] || continue
        if [[ -z "$best" || "$sock" -nt "$best" ]]; then best="$sock"; fi
    done
    [[ -n "$best" ]] && display="$(basename "$best")"
fi

# The IPC call needs the compositor signature as well as the display. When it
# was stripped by sudo, recover it from the target user's runtime dir.
signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [[ -z "$signature" ]]; then
    for d in "$runtime_dir"/hypr/*; do
        [[ -d "$d" ]] && signature="$(basename "$d")"
    done
fi

as_target() {
    if [[ $(id -u) -eq 0 && "$target_user" != root ]] && command -v runuser >/dev/null 2>&1; then
        runuser -u "$target_user" -- env "$@"
    else
        env "$@"
    fi
}

if ! command -v qs >/dev/null 2>&1; then
    echo "$PROG: qs not found; QML will be picked up on next shell start"
    exit 0
fi
if [[ -z "$display" ]]; then
    echo "$PROG: no Wayland socket for $target_user; skipping live reload" >&2
    exit 0
fi

env_args=("WAYLAND_DISPLAY=$display" "XDG_RUNTIME_DIR=$runtime_dir")
[[ -n "$signature" ]] && env_args+=("HYPRLAND_INSTANCE_SIGNATURE=$signature")

# A reload while the lock surface is up destroys it (incident 2026-11-12).
state="$(as_target "${env_args[@]}" qs -c end4-pC ipc call lock status 2>/dev/null)" || state=""
if [[ "$state" == "locked" ]]; then
    echo "$PROG: session is locked -- skipping shell reload"
    exit 0
fi

if as_target "${env_args[@]}" qs -c end4-pC ipc show >/dev/null 2>&1; then
    if as_target "${env_args[@]}" qs -c end4-pC ipc call wallpapers reloadShell >/dev/null 2>&1; then
        echo "$PROG: quickshell theme reloaded via IPC"
    else
        echo "$PROG: IPC reload failed; run Super+/ reload bind manually" >&2
        exit 1
    fi
else
    echo "$PROG: no running shell; starting one from $target_home/.config/quickshell/end4-pC"
    as_target "${env_args[@]}" qs -n -p "$target_home/.config/quickshell/end4-pC" >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi
