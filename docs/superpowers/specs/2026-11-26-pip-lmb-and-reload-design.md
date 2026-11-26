# PiP LMB grab and theme-reload bind — short design

## Intent
Make a plain left-button press grab/move the PiP window, and make `CTRL+SUPER+R` actually reload the running theme. Keep normal LMB selection and clicks everywhere else.

## Findings
- The only draggable binds are `SUPER+LMB` (`window`), `SUPER+RMB` (resize) and no-modifier MMB. Plain LMB drag was removed in `6f054c8` because it broke left-button use; `b5538c7` restored it only with SUPER.
- `CTRL+SUPER+R` is registered, but its command runs `qs -c end4-pC ipc call wallpapers reloadShell` with the inherited `DISPLAY=:1`. The running shell is on `wayland/wayland-1`, so the IPC call fails ("No running instances on x11/:1") and falls through to `qs -p ...`, which does not reload the existing shell. The IPC call succeeds with `WAYLAND_DISPLAY=wayland-1`.
- Escape/record changes are committed but need the theme reload to be live; after reloading, Escape closed the tested sidebar and OSD.

## Goals / non-goals
- Goal: plain LMB drag moves the PiP window; clicks on PiP still reach it; other windows keep normal LMB behavior.
- Goal: `CTRL+SUPER+R` reloads the running shell.
- Non-goal: changing global LMB behavior, the tap-Super launcher, or clipboard/desktop-selection providers (separate track).
- Anti-goal: a global plain-LMB drag bind that swallows text selection.

## Approaches
1. **Dynamic PiP-only LMB bind (chosen).** In the catalog preamble, use `hl.on("window.active", ...)` to bind plain `mouse:272` with `{ mouse = true }` only while the active window matches `class == "zen"` and `title == "Picture-in-Picture"`, and unbind it on every other focus change. Add `binds.drag_threshold = 10` so a short click is not consumed and only a drag moves the window. `SUPER+LMB`, `SUPER+RMB` and MMB drag stay untouched. Cost: the dynamic bind depends on Hyprland's active-window event; if focus is not reported for PiP, a reload is needed to re-arm it.
2. **Global guarded LMB bind.** One global bind with a Lua guard and drag threshold. Rejected: if Hyprland does not forward an unconsumed mouse event to the client, this reintroduces the original selection bug.
3. **Window rule.** Rejected: Hyprland has no per-window "drag with LMB" rule property.

## Implementation decisions (my calls)
- `drag_threshold = 10` is applied; short clicks on PiP remain usable (my call, since the click-vs-grab question was left open).
- The reload command becomes `env WAYLAND_DISPLAY=wayland-1 qs -c $qsConfig ipc call wallpapers reloadShell || qs -n -p $HOME/.config/quickshell/$qsConfig`. Adding `-n` to the fallback prevents a duplicate shell if IPC still fails.
- New behavior is covered by static tests before the generator output is regenerated.
- Reload of the running theme is triggered by the user or with their explicit permission, never by killing/restarting processes.

## What is left to the builder
Follow the plan derived from this design; verify catalog generation, Lua syntax, validator parity, the full test suite, and a user-triggered reload.
