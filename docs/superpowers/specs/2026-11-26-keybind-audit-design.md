# Keybind Audit — Short Design (approved 2026-11-26)

## Intent
`end4-pC` moved keybinds into a JSON catalog + user overlay, generated into Hyprland Lua and a Quickshell command bridge. A one-time manual check proved the chain consistent, but "verify them all" must be repeatable and must never disturb the running desktop (no reboot, kill, shutdown, restart, or injected keystrokes).

## Goals
- Inventory all 212 catalog binds and classify each as healthy / dead-by-design / needs-live-check / unsafe-to-test.
- Verify catalog → overlay → generated Lua/JSON → live Hyprland state, including every global-shortcut dispatch target.
- Statically validate all 51 command bridges (`bash -n`, executable/script/IPC existence) without executing them.
- Exit non-zero when a structural regression is found.

## Non-goals / Anti-goals
- No activation of any bind; no `hyprctl reload`, no process management, no session/lock/reload binds triggered.
- No writes to user config (`~/.config/hypr/...`, `~/.config/quickshell/...`).
- Not a functional test of GUI outcomes — runtime behavior stays explicitly marked as unverified.

## Constraints
- Python 3 standard library only; reuse `scripts/hyprland/generate_keybinds.py::merged_binds` and constants rather than reimplementing merge rules.
- Hyprland 0.57.2: `release = true` binds never fire; `hl.dsp.exec_cmd()` is a no-op unless wrapped by `hl.dispatch()`; those are known-by-design, not regressions.
- Live data comes only from `hyprctl binds -j`, `hyprctl globalshortcuts`, and `hyprctl configerrors`.

## Approaches
- **A (chosen): standalone Python diagnostic** — pure analysis functions + tests, one CLI that optionally reads live `hyprctl` output. Reuses the generator's merge, adds live-registration and command-dependency checks the existing validator cannot do.
- B: shell wrapper over existing validator/generator — cheaper but cannot classify individual binds or validate command dependencies.
- C: extend `validate_keybind_catalog.py` — would mix frozen-catalog validation with live-state auditing and add noise to CI.

## Parts left to the builder
- `scripts/diagnostics/keybind-audit.py` (analysis + report CLI).
- `tests/test_keybind_audit.py` (unit tests for pure functions).
- Run the audit once and report findings; no live key activation.
