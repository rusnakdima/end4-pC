# Window opacity rule (ignore global opacity)

> Add a per-window rule that disables global opacity for a window, mirroring the existing tiling/stacking/span rules.

**Status**: Completed
**Created**: 2026-11-14
**Owner**: frontend-engineer

## Goal
Users can mark individual windows to ignore the global window opacity (fully opaque) while all other windows follow `decoration:active_opacity` / `inactive_opacity`. The rule is edited in the same "App window rules" list as tiling/stacking/span.

## Context
- Global opacity: `modules/ii/settings/pages/HyprlandDecoration.qml` (Active/Inactive Opacity) → `Config.options.hyprland.decoration.*Opacity` → `HyprlandConfig`.
- Per-app rules: `services/WindowMode.qml` writes `hyprland/shellOverrides/windowMode.lua`; `modules/common/widgets/AppWindowRules.qml` edits the list.
- Span rules already force `opacity = "1 1"`, providing the precedent.
- Architecture decision: `docs/decisions/adr-window-opacity-rules.md` (Proposed).

## Constraints
- Reuse existing AppWindowRules/WindowMode infrastructure (no second rule list).
- Backward compatible with configs lacking `disableOpacity`.
- Do not change float behaviour (opacity is orthogonal to mode).
- Tests in `tests/shell-tests/tst_window_mode.qml` and `tst_app_window_rules.qml` must pass.

## Tasks

| # | Task | Agent | Priority | Status | Dependencies |
|---|------|-------|----------|--------|--------------|
| 1 | Update `WindowMode.rulesSource` skip condition + emit the opaque effect when `disableOpacity` | backend-engineer | 1 | DONE | — |
| 2 | Add `disableOpacity` to `AppWindowRules` snapshot/configSnapshot/load/commit + toggle UI | frontend-engineer | 1 | DONE | 1 |
| 3 | Add translations for toggle label | docs-curator | 2 | DONE | 2 |
| 4 | Extend tests with opacity cases | qa-reviewer | 2 | DONE | 1,2 |
| 5 | Verify qml-compile-check + shell tests | qa-reviewer | 3 | DONE | 1,2,3,4 |

## Done When
- [x] A rule with `disableOpacity: true` produces `opaque = true` in `windowMode.lua`.
- [x] A rule redundant in mode but with `disableOpacity: true` is still written.
- [x] Existing tests pass; new opacity cases pass.
- [x] Toggle visible and persisted in settings.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-11-14 | Use boolean `disableOpacity` on existing rule | Orthogonal to mode; minimal change (ADR) |

## Progress Notes
- [2026-11-14] Plan created
- [2026-11-14] Implementation complete: WindowMode.rulesSource + AppWindowRules toggle + tests (window_mode 42/0)
- [2026-11-15] Root cause of "opacity is ignored" found by measuring the
  rendered pixels of probe windows over a green backdrop: Hyprland treats
  `opacity` as a **product**, so the emitted `opacity = "1 1"` multiplied
  the global 0.85 by 1 and did nothing (measured 0.839 = exactly the no-rule
  control). Emission switched to the `opaque = true` effect (measured 1.0);
  `setOpacity()` now writes the `*_override` flags as well and clears them
  when the rule is switched off, tracked in
  `Persistent.states.windowMode.ownedOpacity`.
- [2026-11-15] Title/subclass fixes in `AppWindowRules`: the title field
  wrote a non-existent `title` role (real role: `winTitle`), so a typed
  subclass was dropped on every commit; the picker wrote a live browser tab
  title as a hard AND constraint. The picker now offers one entry per app
  *and* one per single window (class + title), so a PiP can be picked
  without widening the rule to the whole browser.
