# Keyboard RGB (colour from Settings)

> Set the keyboard backlight colour from Settings, follow the wallpaper's colour, and make it work at the system level — because no LED app can drive this machine's keyboard.

**Status**: Completed
**Created**: 2026-11-15
**Owner**: general

## Goal
Users pick a keyboard colour from a palette in Settings → Keyboard, adjust its
brightness, toggle rainbow cycling, and turn on *Match the wallpaper colour* so
the keyboard follows the theme — all through a supported system path rather
than an app that cannot reach the hardware.

## Context
- Hardware: Maibenben X16C (TongFang QC71) with the DKMS `qc71_laptop` driver,
  loaded with `debugregs=1`.
- **Why nothing else worked**: the driver returns `-ENODEV` for its LED device
  because EC `SUPPORT_1` (0x0765) reads `0xa1` (bit 6 clear) —
  `dmesg: failed to initialize led_lightbar submodule: -19`. No ITE8291 USB
  device enumerates. `uniwill_laptop` and the qc71 `lightbar_*` registers both
  address the *lightbar*, which this chassis does not have.
- **The keyboard**: 1-zone RGB at EC `0x0769/6a/6b` (0…50 per channel),
  colour latch `0x0767 |= 0x20`, brightness in `0x078c` bits 7-5 with the
  `0x10` latch. Confirmed because those registers read `(0,50,50)` — the cyan
  that was visible.
- Theme side: `services/Brightness.qml` (singleton `Brightness.kbMonitor`),
  `modules/ii/settings/pages/KeyboardConfig.qml`, `Config.options.light.keyboardColor`.
- Architecture decision: `docs/decisions/adr-keyboard-rgb-control.md` (Accepted).

## Constraints
- Exactly one sudoers grant, scoped to a single helper binary; arguments are
  never passed through a shell.
- Wallpaper matching must use the **same mechanism** as the shell's dynamic
  appearance (`MaterialThemeLoader` → `Appearance.colors`), not a second
  sampler.
- One switch governs the source (*Match the wallpaper colour*); a hand-picked
  colour turns it off.
- A rejected argument must never write to the EC.
- `tests/test_kbd_rgb.sh` must stay hermetic (no root, no hardware).

## Tasks

| # | Task | Agent | Priority | Status | Dependencies |
|---|------|-------|----------|--------|--------------|
| 1 | Identify the real control path; rule out LED class / ITE8291 / uniwill / lightbar | general | 1 | DONE | — |
| 2 | Helper `scripts/keyboard-rgb/kbd-rgb` (probe/set/off/save/restore/dump, one JSON line) | general | 1 | DONE | 1 |
| 3 | `setup-keyboard-rgb.sh`: helper, sudoers, boot unit, legacy-service cleanup | general | 1 | DONE | 2 |
| 4 | Rewrite `Brightness.kbMonitor` to call the helper, debounced, no post-write probe | general | 1 | DONE | 2 |
| 5 | Settings UI: palette, brightness slider, rainbow toggle, one wallpaper switch, accent role | general | 1 | DONE | 4 |
| 6 | Wallpaper match on `Appearance.colors` with full-saturation rendering for hardware | general | 1 | DONE | 4,5 |
| 7 | Contract test `tests/test_kbd_rgb.sh` against a synthetic EC image | general | 2 | DONE | 2 |
| 8 | Docs: `scripts/keyboard-rgb/README.md`, ADR, plan, root README section | general | 2 | DONE | 1 |
| 9 | Fix ownership, commit and push | general | 2 | DONE | 2–8 |

## Done When
- [x] A palette cell click changes the keyboard colour within ~0.8 s.
- [x] *Match the wallpaper colour* recolours at the same moment as the rest of
      the dynamic UI, through `Appearance.colors`.
- [x] Colour is vivid (full saturation), not the pale UI tone.
- [x] Brightness slider visibly dims; rainbow toggle works and stays on.
- [x] Colour survives a reboot (`/var/lib/ambxst/kbd-rgb.state` + enabled unit).
- [x] `bash tests/test_kbd_rgb.sh` and `./tests/qml-compile-check.sh` pass.
- [x] Every file in the tree owned by `dmitriy`, not `root`.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-11-15 | Raw EC file behind one sudo helper, no driver patch | The patchable LED device is the lightbar, not the keyboard (ADR) |
| 2026-11-15 | Reproduce the vendor driver's quantisation and latches | Both latches are mandatory; raw pokes silently do nothing |
| 2026-11-15 | "Off" = darkest achievable | EC rewrites brightness 0 and the off bit within ~2 s |
| 2026-11-15 | Follow `Appearance.colors`, not a wallpaper sample | Same mechanism as every dynamic UI element |
| 2026-11-15 | One switch, manual pick turns it off | One source of truth for the panel |
| 2026-11-15 | Read 5 registers, not a 48-byte span | Each EC byte costs ~55 ms; span ×2 was 5.76 s |

## Progress Notes
- [2026-11-15] Diagnosis: `exec([])` in the old probe ran an **empty command**,
  so `available` was permanently false and every control was hidden. `Qt.color()`
  in this Qt build exposes `r/g/b` but **no `isValid`, no `name()`, no `h/s/v`**,
  so `!c.isValid` rejected every colour, `c.name()` threw and `hue` became NaN
  (dead sliders). A probe landing while an apply was queued reverted the
  rainbow toggle, and the queued write then matched the old key and never ran.
  `CustomColorSelectionArray` renders `option.color`, which the swatch table
  never had — hence blank circles. `Gradient` defaults to top-to-bottom, so the
  saturation overlay ran down instead of across.
- [2026-11-15] Performance: each EC byte is a ~55 ms WMI round trip. The first
  implementation read a 48-byte span twice per change (2.7 s ×2) for 5.76 s; it
  now reads only the five registers it needs — `set` 0.72 s, `probe` 0.36 s —
  and the post-write `probe()` was dropped for the helper's own reply, taking a
  colour change from ~8.4 s to ~0.8 s.
- [2026-11-15] Hardware limits found by measurement, not assumption: 51 colour
  steps/channel, 4 brightness steps, and no true off (both the zero-brightness
  and off-bit writes are undone by the EC within ~2 s).
- [2026-11-15] A rival source (`Appearance.wallpaperDominant`, sampled with
  `ColorQuantizer`) was added and then removed so exactly one mechanism remains.
