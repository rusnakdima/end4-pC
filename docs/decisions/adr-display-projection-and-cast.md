# ADR 003: Display projection and Cast panes

**Status**: Accepted
**Date**: 2026-11-18

## Context

The shell already had a Displays pane (per-monitor mode, scale, orientation,
HDR) and a VNC server pane. Two user needs were not covered:

1. Windows-style *projection modes* for wired external monitors: PC screen
   only, Duplicate, Extend, Second screen only.
2. Casting the desktop to a TV over the network, both to a nearby TV over
   Wi‑Fi Direct (Miracast) and to a TV/receiver reachable over LAN or Tailscale.

## Decision

### Wired projection

Implement projection as pure layout math in a testable singleton,
`ProjectionUtils.qml`. `MonitorConfigOption.qml` applies the resulting patches
to Hyprland and persists them to `~/.config/hypr/monitors.lua` through the
existing `monitor_configurator.py`, which already supports the `mirror` field.

- Duplicate uses Hyprland's native `mirror, <source>` monitor rule, not two
  manually aligned outputs.
- The pre-projection layout is saved per output in
  `~/.config/end4-pC/projection.json` so switching modes restores the user's
  previous arrangement and a compositor reload or cable change re-applies the
  chosen mode.
- No new config schema keys and no new dependencies.

### Casting

Cast reuses the VNC controller architecture: a QML singleton
(`services/Cast.qml`) talks only to a JSON CLI helper
(`scripts/cast/end4pc-cast`) that owns config, discovery and the backend
process. The pane never writes shell config or starts processes itself.

- **Local** mode uses `waycast` (MIT, wlroots/Hyprland-native) for Miracast:
  discover, mirror or extend, audio and codec selection.
- **Remote** mode uses `fluxcast` for DLNA/Cast by explicit address. Miracast
  is Wi‑Fi Direct P2P and cannot traverse a LAN or VPN, so the two paths are
  deliberately separate and labelled accordingly in the UI.
- One-time provisioning lives in `optional/cast/` and follows the idempotent
  installer pattern used by the hotspot and VNC helpers. Privileged steps are
  printed, never executed by the shell GUI.

## Consequences

- The four projection modes are unit-tested without a compositor through the
  hosted QML harness.
- Cast correctness against a real TV cannot be verified in CI; the helper's
  `doctor` and graceful "backend not installed" state make failures explicit.
- New UI strings use `Translation.tr("…")` with English fallback, so the pinned
  translation key count (1814) is unchanged.
