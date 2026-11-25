# Source this before launching X11 clients (TigerVNC's vncviewer, Remmina,
# xfreerdp, ...) when the calling shell did not inherit DISPLAY/XAUTHORITY.
# Hyprland's Xwayland is normally :1; a headless/other session may differ,
# so prefer the X socket owned by the current user and fall back to :1.
if [ -z "${DISPLAY:-}" ]; then
    _gui_me=$(id -un)
    for _gui_sock in /tmp/.X11-unix/X[0-9]; do
        [ -S "$_gui_sock" ] || continue
        [ "$(stat -c %U "$_gui_sock" 2>/dev/null || true)" = "$_gui_me" ] || continue
        DISPLAY=":${_gui_sock##*/X}"
        export DISPLAY
        break
    done
    if [ -z "${DISPLAY:-}" ]; then
        DISPLAY=:1
        export DISPLAY
    fi
    unset _gui_me _gui_sock
fi

if [ -z "${XAUTHORITY:-}" ]; then
    # Prefer the cookie that matches the user's Xwayland socket (root's own
    # ~/.Xauthority is often stale).
    if [ -r /home/dmitriy/.Xauthority ]; then
        XAUTHORITY=/home/dmitriy/.Xauthority
        export XAUTHORITY
    elif [ -r "${HOME:-}/.Xauthority" ]; then
        XAUTHORITY="${HOME}/.Xauthority"
        export XAUTHORITY
    fi
fi
