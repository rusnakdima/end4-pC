# General settings: seconds-aware time format and date presets

> The second-precision switch only changed the clock's tick rate, not the stored time format, so the selector still showed `hh:mm` and surfaces that read the format kept rendering minutes only. Add ready-made date formats next to the manual field.

**Status**: Active
**Created**: 2026-11-18
**Owner**: general

## Goal

1. Enabling **Second precision** writes the selected time format with seconds (`hh:mm` → `hh:mm:ss`, `h:mm ap` → `h:mm:ss ap`, `h:mm AP` → `h:mm:ss AP`); disabling removes them again.
2. The **Format** selector keeps showing which of the three base formats is selected while the switch changes, and the preview/clock use the resulting format.
3. An existing config that already has `secondPrecision: true` but `format: "hh:mm"` (the live state on this machine) renders seconds without the user having to toggle the switch first.
4. **Date String Format** gets a ready-made list of common patterns while the existing manual input field stays available for arbitrary patterns.

## Context

- `modules/ii/settings/pages/GeneralConfig.qml:72-80` fakes seconds in the preview only; it never writes them into `Config.options.time.format`.
- `services/DateTime.qml:25` formats `DateTime.time` with `Config.options.time.format` verbatim, so enabling the switch does not add seconds to the bar/desktop clock. The live config has `"secondPrecision": true` and `"format": "hh:mm"`.
- The format selector (`GeneralConfig.qml:106-123`) matches the stored format exactly; a seconds-suffixed value would leave every button unselected.
- `services/SettingsQuickControls.qml:467-481` exposes the same two settings to settings search and has the same coupling.
- `modules/common/functions/StringUtils.qml` is the natural home for the pure format-string helpers and already has a hosted test (`tests/shell-tests/tst_strings.qml`).
- Date patterns are displayed as patterns themselves, so the preset list needs no new translation keys. `Presets` and `Date String Format` already exist in `translations/en_US.json`.

## Constraints

- Do not add or remove translation keys; `tst_translation.qml` asserts the exact `en_US` key count (1814).
- Keep `Config.options.time.format` as the persisted source of truth and `secondPrecision` as the user-facing switch.
- Do not change the `hyprlock.conf` `TIME`/`TIME12` switching semantics: 24-hour formats still use `TIME`.
- No new dependencies, no config schema change.

## Tasks

| # | Task | Agent | Priority | Status | Dependencies |
|---|------|-------|----------|--------|--------------|
| 1 | Add seconds helpers to `StringUtils` | general | 1 | DONE | — |
| 2 | Wire the General pane switch/selector/preview | frontend | 1 | DONE | 1 |
| 3 | Normalize the effective format in `DateTime` | backend | 1 | DONE | 1 |
| 4 | Keep settings-search controls consistent | frontend | 1 | DONE | 1 |
| 5 | Add date-format presets next to the manual field | frontend | 1 | DONE | — |
| 6 | Add helper tests and run the gates | qa | 2 | DONE | 1-5 |

### Task 1 — format helpers

In `StringUtils.qml`:

- `formatHasSeconds(format)` — true when the pattern contains an `s`/`ss` field (not a letter inside a word).
- `removeSecondsFromFormat(format)` — strips the field and its `:` separator, trims the result.
- `setFormatSeconds(format, enabled)` — returns the pattern with `:ss` inserted before a trailing `ap`/`AP` or appended, and the unchanged pattern when seconds are already present; when disabling, delegates to the remover.

### Task 2 — General pane

- Format selector: compare and select with `StringUtils.removeSecondsFromFormat(DateTime.timeFormat)`; on selection keep the current precision by writing `StringUtils.setFormatSeconds(value, secondPrecision)`. Keep the `TIME`/`TIME12` sed branch based on whether the chosen format has `ap`.
- Second precision switch: write `StringUtils.setFormatSeconds(currentFormat, checked)` before storing the boolean.
- Preview: format `previewCard.now` with `DateTime.timeFormat`; tick every second when it has seconds, otherwise every 15 s.
- Clock format field: display the effective format (`DateTime.timeFormat`), so opening the pane repairs the stored value; keep writing the typed value.

### Task 3 — effective format

`DateTime` exposes `timeFormat = StringUtils.setFormatSeconds(storedFormat, secondPrecision)` and uses it for `DateTime.time` and `use12HourFormat`. This makes the live, already-inconsistent config show seconds immediately.

### Task 4 — settings search

Use the same helpers in `SettingsQuickControls.qml` for `general:Format` (base value for comparison, seconds preserved on write) and `general:Second precision` (rewrite the format when toggling).

### Task 5 — date presets

Add a `ConfigComboBox` labelled with the existing `Presets` key, with the pattern as both the display name and the value. When the current pattern is custom, prepend it so the combo still shows the active value. Keep the existing `Date String Format` `ConfigTextArea` below it.

### Task 6 — verification

- `tests/qml-compile-check.sh` for the touched files and the whole tree.
- `QUICKSHELL_TEST_FILES=tst_strings.qml` (new cases) and the full hosted suite against the known baseline (2 pre-existing failures: `tst_bar_content`, `tst_thumbnail_image`).
- `tests/functional-coverage.sh` and `tests/icon-audit.py` if icons changed.

## Done When

- [x] Toggling Second precision on writes `hh:mm:ss` / `h:mm:ss ap` / `h:mm:ss AP`; toggling off returns the base format.
- [x] The Format selector shows the chosen base format in both states.
- [x] A config with `secondPrecision: true` and `format: "hh:mm"` renders seconds immediately.
- [x] The General pane offers date presets and still accepts a manual pattern.
- [x] No translation keys added; compile check and hosted tests show no new failures.

## Progress Notes

- [2026-11-18] `StringUtils` gained `formatHasSeconds`, `removeSecondsFromFormat` and `setFormatSeconds`; `tst_strings.qml` covers the base, 12-hour and already-correct cases.
- [2026-11-18] `GeneralConfig.qml`: the switch rewrites the stored format, the selector compares against the seconds-free base, the preview formats with `DateTime.timeFormat`, and the clock field shows the effective value (opening the pane repairs an old `secondPrecision: true` + `hh:mm` config).
- [2026-11-18] `DateTime.timeFormat` normalizes the stored format with the switch, so the bar/desktop clocks render the live config's seconds immediately; `use12HourFormat` follows the effective value.
- [2026-11-18] `SettingsQuickControls.qml` uses the same helpers, so the settings search result behaves like the General pane.
- [2026-11-18] Date presets are a `Presets` combo (pattern shown verbatim, custom value prepended) above the unchanged `Date String Format` field. No new translation keys.

## Verification

- `bash tests/qml-compile-check.sh` (whole tree) → **PASS**.
- `QUICKSHELL_TEST_FILES=tst_strings.qml bash tests/run-shell-tests.sh` → **38/38 passed**.
- Full hosted suite: 33 passed / 4 failed. The failures are the known `tst_bar_content` import error and `tst_thumbnail_image` candidate-order assertion, plus `tst_idle_persistence` (flaky; passes alone) and `tst_managed_keybinds` (2/5 on a clean HEAD worktree as well, unrelated to this change).
- A throwaway hosted probe confirmed `DateTime.timeFormat` equals `StringUtils.setFormatSeconds(storedFormat, secondPrecision)` against the live config; the probe file was removed.
- `tests/functional-coverage.sh` still reports only the pre-existing unmapped areas; `tests/icon-audit.py` → **PASS** (620 icons).
