# Keybind Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repeatable, strictly read-only audit that verifies every end4-pC keybind from JSON catalog through live Hyprland state and reports which binds are healthy, dead-by-design, or unverifiable without activation.

**Architecture:** A Python CLI reuses `generate_keybinds.merged_binds()` to build the effective set, then runs four checks: catalog/overlay-to-live bind parity, global-shortcut target registration, command-bridge dependency validation, and per-bind classification. Pure functions are unit-tested; only the CLI entrypoint touches the live system via `hyprctl` subprocesses.

**Tech Stack:** Python 3 stdlib, `unittest`, existing `scripts/hyprland/generate_keybinds.py`, `hyprctl` JSON output.

**Spec:** `docs/superpowers/specs/2026-11-26-keybind-audit-design.md`

## Global Constraints
- Never execute a keybind, call `hyprctl dispatch`, reload Hyprland, or kill/restart any process.
- Never write to `~/.config` — all checks are read-only; generated comparisons may use temp dirs only.
- Classify `release = true`, overlay-disabled, unbound, and whitelisted duplicate binds as dead-by-design, not failures.
- Do not treat `TEST_ALIVE` IPC misses as failures — those are intentional fallthroughs.

## Review Focus
- Overlay override/disable correctness: every catalog id must appear in the report exactly once with its effective combo — test `classify_binds` with an override, a disable, and a runtime-only id.
- Missing global shortcut: an unregistered `quickshell:` target must be reported — test `audit_global_targets` with a deliberately missing target.
- Broken command bridge: invalid `bash -n`, missing executable, missing script path, or missing IPC method must be reported — test `audit_commands` with fixtures for each.
- Live parity: a loaded bind set missing an effective combo must be reported — test `audit_live_binds` with a synthetic bind list.
- Unsafe-to-test binds (session/reload/lock/shutdown) must be classified as such and never dispatched — test classification of those categories.

---

### Task 1: Read-only keybind audit CLI

**Files:**
- Create: `scripts/diagnostics/keybind-audit.py`
- Modify: `scripts/hyprland/generate_keybinds.py` (no change expected; import only)
- Test: `tests/test_keybind_audit.py`

**Interfaces:**
- Consumes: `generate_keybinds.merged_binds(catalog, overlay, exec_mode='bridge')`, `generate_keybinds.parse_combo(combo)`, `generate_keybinds.MODIFIERS`.
- Produces: `audit(args=None) -> int` (CLI exit code), `classify_binds(catalog, overlay, live_binds) -> dict`, `audit_global_targets(lua_text, registered) -> list[str]`, `audit_commands(commands, home, repo) -> list[str]`, `audit_live_binds(effective, live_binds) -> list[str]`, `render_report(result) -> str`.

- [ ] **Step 1: Write failing tests** in `tests/test_keybind_audit.py` for the five Review Focus cases above, using small fixture dicts (no live Hyprland calls).
- [ ] **Step 2: Run `python3 -m unittest tests.test_keybind_audit -v` and confirm it fails on missing module.**
- [ ] **Step 3: Implement `scripts/diagnostics/keybind-audit.py`** with pure functions and a `main()` that reads catalog/overlay/generated files, optionally runs `hyprctl binds -j`, `hyprctl globalshortcuts`, `hyprctl configerrors`, prints `render_report(...)`, and returns 1 if any structural issue exists.
- [ ] **Step 4: Run the unit tests and confirm they pass.**
- [ ] **Step 5: Run the audit read-only** against the live system (`python3 scripts/diagnostics/keybind-audit.py`) and confirm no process is restarted, no bind activated.
- [ ] **Step 6: Commit** with message `feat(diagnostics): add read-only keybind audit`.
