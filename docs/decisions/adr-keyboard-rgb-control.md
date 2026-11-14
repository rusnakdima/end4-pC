# ADR: Keyboard RGB driven through the EC register file

- Status: Accepted
- Date: 2026-11-15
- Supersedes: none

## Context

The fork needs the keyboard backlight colour to be settable from Settings, to
follow the wallpaper, and to work at the system level — because no LED
application can drive this machine's keyboard. Four candidate paths exist and
three of them are dead on this hardware:

* **The driver's own LED device.** `qc71_laptop` refuses to register one:
  `dmesg` reports `failed to initialize led_lightbar submodule: -19`, because
  `led_lightbar.c` returns `-ENODEV` when `qc71_features.lightbar` is false,
  and EC `SUPPORT_1` (0x0765) reads `0xa1` — **bit 6 clear**. Forcing that gate
  open would only expose the *lightbar* (0x0749–4b), which `uw_lightbar_init()`
  further restricts to DMI board names (`LAPQC71A`, `LAPQC71B`, …) this machine
  does not have (`board_name` is `X16C`) — and this chassis has no lightbar at
  all.
* **ITE8291.** `tuxedo-drivers` ships `ite_8291_lb`, but it binds USB IDs
  `048d:6010/7000/7001`. `lsusb` shows no such device; the only HID device is
  the touchpad.
* **`uniwill_laptop`'s multicolor LED.** Loading it creates
  `uniwill:multicolor:status`, but it maps onto the *same lightbar registers*,
  so writes land and nothing visible changes. It also pins EC 0x0741 (manual
  fan control) as a side effect, which has to be undone.
* **qc71's `lightbar_*` debugfs registers.** Writable and readable, but they
  are the lightbar, not the keyboard.

The keyboard is a 1-zone RGB zone addressed elsewhere in EC RAM. Its map is
documented in `tuxedo-drivers` (`uniwill_interfaces.h` / `uniwill_leds.h`) and
was confirmed empirically: before this work those registers read `(0, 50, 50)`,
exactly `tf_convert_rgb_range(0, 255, 255)` — the cyan the keyboard was
showing.

## Decision

1. **One root helper**, `/usr/local/bin/kbd-rgb`, talking to the raw EC file
   `/sys/kernel/debug/qc71_laptop/ec` (which only exists with `debugregs=1`).
   It prints exactly one line of JSON and exits 0/1; the shell calls it with
   `sudo -n` and never passes arguments through a shell. Sudoers grants that
   single binary and nothing else.
2. **No LED-class-device patch.** Rejected: that device is the lightbar, not
   the keyboard, so patching the driver would have produced a controllable LED
   for hardware this machine does not have.
3. **Reproduce the vendor driver's own sequence** instead of inventing one:
   colour conversion `value * 200 / (255 * 4)` (0…50 per channel), then the
   colour latch `0x0767 |= 0x20`, then brightness in `0x078c` bits 7-5 with the
   `0x10` latch. Both latches are mandatory — changing either register without
   its latch does nothing at all, which is why raw register pokes look broken.
4. **Never write `0,0,0`**: the EC treats it as "use my defaults" and lights the
   panel itself, so black is expressed as the lowest level that holds.
5. **No true off.** Brightness `0` and the off bit are both rewritten by the EC
   within ~2 s, so "off" means *darkest achievable* (level 1 on every channel)
   and `probe` reports that honestly.
6. **Wallpaper matching reuses `Appearance.colors`** — the object
   `MaterialThemeLoader` rewrites when matugen regenerates the palette — so it
   changes exactly when and because the rest of the dynamic UI changes. The
   role is configurable (default `colPrimaryActive`, because plain
   `colPrimary` is a UI-surface tone and reads as washed out on a keyboard),
   and the followed colour keeps that role's hue and lightness but is taken at
   full saturation, which is what the palette's lower rows show.
7. **One switch governs the source**: *Match the wallpaper colour*. A colour
   picked by hand is by definition not the wallpaper's, so it flips the switch
   off rather than letting two sources fight over the panel.

## Diagram

```
Settings → Keyboard ──► services/Brightness.qml (kbMonitor, debounced 80ms)
                              │  sudo -n /usr/local/bin/kbd-rgb set --color …
                              ▼
                     /usr/local/bin/kbd-rgb        ← tests/test_kbd_rgb.sh
                              │  one JSON line
                              ▼
                     /sys/kernel/debug/qc71_laptop/ec   (offset = EC address)
                              │
                     0x0769/6a/6b colour · 0x0767 latch · 0x078c brightness

MaterialThemeLoader ──watchChanges──► Appearance.colors ──onChanged──► follow
```

## Alternatives Considered

* **Patch `qc71_laptop` to register its LED device** — rejected; it registers
  the lightbar, and the lightbar does not exist on this chassis.
* **Drive `uniwill:multicolor:status`** — rejected; it is the same lightbar
  register block, plus a fan-control side effect.
* **Sample the wallpaper directly with `ColorQuantizer`** — rejected; it was a
  second, parallel mechanism beside the one the whole theme already uses, and
  it drifted from the UI's colour.
* **Bind wallpaper matching to a fixed Material role** — rejected in favour of
  a selectable role, because `colPrimary` is pale by design and the shade needs
  to be right on hardware.

## Consequences

* Requires `debugregs=1` in `/etc/modprobe.d/qc71_laptop.conf`, a root helper
  and one sudoers rule. `--check` verifies all three and reports which is
  missing; `sudo -n` cannot prompt from a background process, so a missing rule
  surfaces as `sudo: a password is required` in the page's error box.
* Colour fidelity is bounded by the hardware: **51 steps per channel** (~132 k
  colours) and **4 brightness steps** (25/50/75/100 %).
* Latency is bounded by the EC: **each byte costs a ~55 ms WMI round trip**, so
  the helper reads only the five registers it needs — a change takes ~0.7 s,
  down from 5.76 s when it read a 48-byte span twice.
* A kernel update is fine: `qc71_laptop` is a DKMS package with
  `AUTOINSTALL=yes`.
* Removing the helper leaves the keyboard at whatever the EC last held.

## Follow-up Validation

| Check | Result |
|---|---|
| `bash tests/test_kbd_rgb.sh` | PASS (13 contract cases against a synthetic EC image) |
| `./tests/qml-compile-check.sh` | PASS |
| `./tests/run-shell-tests.sh` | 29/33; the 4 failures pre-date this work |
| `sudo -n kbd-rgb probe` as the theme user | `available:true`, colour matches the panel |
| Colour change round trip | 5.76 s → 0.72 s |
| Register-level proof | `0x0769/6a/6b` held `(0,50,50)` = the visible cyan |
| Fans after testing | `ctrl_1=0x80`, `fan_ctrl=0x80` (`FAN_CTRL_ADDR=0x0751`, never written), ~2300/2150 rpm |

## Implementation tasks (for /work)

1. System: `scripts/keyboard-rgb/kbd-rgb` helper + `setup-keyboard-rgb.sh`
   (helper, sudoers, boot unit, legacy-service cleanup).
2. Service: rewrite `Brightness.kbMonitor` to call the helper, debounce, drop
   the post-write probe.
3. Settings: palette picker, brightness slider, rainbow toggle, single
   wallpaper-match switch and accent-role selector.
4. Tests: `tests/test_kbd_rgb.sh`, hermetic via `KBD_RGB_EC`.
5. Docs: `scripts/keyboard-rgb/README.md`, this ADR, `docs/plans/work/002`.
