# Keyboard RGB — system setup guide

The end4-pC theme ships a **keyboard colour** feature (Settings → Keyboard,
plus a sidebar brightness slider). This directory contains everything needed to
make it work on a machine — the root helper, an idempotent installer, a contract
test, and this guide.

```
scripts/keyboard-rgb/
├── README.md                 ← this guide
├── kbd-rgb                   ← the root helper the theme calls (reference copy)
└── setup-keyboard-rgb.sh     ← install / --check / --uninstall
```

Related: `tests/test_kbd_rgb.sh` (contract test) and
`scripts/kbd-backlight-restore.sh` (shim for the old boot path).

---

## 1. The contract (what the theme expects)

`services/Brightness.qml` does **nothing** except shell out to a root helper and
parse one JSON line:

```bash
sudo -n /usr/local/bin/kbd-rgb probe
sudo -n /usr/local/bin/kbd-rgb set --color '#42a5f5' --brightness 100 --mode static
sudo -n /usr/local/bin/kbd-rgb set --color '#ffffff' --mode rainbow
sudo -n /usr/local/bin/kbd-rgb off
```

* Runs as the **theme user** with **NOPASSWD** sudo for exactly this one binary.
  Arguments are passed as an array, never through a shell.
* Output: **one line of JSON**, exit `0` on success and `1` on error —

  ```json
  {"ok":true,"available":true,"backend":"ec","color":"#3da3f5",
   "levels":[12,32,48],"brightness":100,"brightnessLevel":4,
   "mode":"static","rainbow":0,"off":false,"whiteOnly":false,
   "status":128,"modeReg":0}
  {"ok":false,"error":"colour must be #RRGGBB (got 'red')"}
  ```

* `color` is the **closest colour the panel can actually display**, not the one
  requested — the page previews it so the UI can never disagree with the
  keyboard.
* `available:false` (exit 1) means no device: the theme shows a notice instead
  of pretending, and the sidebar slider hides itself.
* State lives in `/var/lib/ambxst/kbd-rgb.state` (`#RRGGBB brightness mode`) and
  is re-applied at boot by `kbd-rgb-restore.service`.

---

## 2. Why nothing else works on this machine

Four obvious paths were checked and ruled out:

| path | verdict |
|---|---|
| **LED class device** | `qc71_laptop` refuses to register one: `dmesg` says `failed to initialize led_lightbar submodule: -19`, because EC `SUPPORT_1` (0x0765) reads `0xa1` and **bit 6 is clear**. `/sys/class/leds/*lightbar*` can never exist. |
| **`rgb:kbd_backlight` / `uniwill:multicolor:status`** | Loading `uniwill_laptop` creates a multicolor LED, but it maps onto the **lightbar** registers (0x0749–4b). Writing it changes those registers and nothing you can see. |
| **ITE8291 HID lightbar** | `tuxedo-drivers` ships `ite_8291_lb`, which binds USB IDs `048d:6010/7000/7001` — **no such device is enumerated** (`lsusb` shows only hubs, wireless, webcam; the single HID device is the touchpad). |
| **lightbar registers 0x0749–4b** | Correct for a lightbar. On this chassis there is none; writing them moves the registers and leaves the keyboard untouched. |

`board_name` is `X16C`, which also misses the DMI list in Tuxedo's
`uw_lightbar_init()` (`LAPQC71A`, `LAPQC71B`, …), so that path is gated off too.

### What actually works

The keyboard is a **1-zone RGB zone** addressed elsewhere in EC RAM. The map is
documented in `tuxedo-drivers` (`uniwill_interfaces.h` / `uniwill_leds.h`), and
this helper reproduces that driver's own sequence rather than inventing one:

| address | meaning |
|---|---|
| `0x0769` | keyboard **red**, 0…50 in the EC (0…255 from the caller) |
| `0x076a` | keyboard **green** |
| `0x076b` | keyboard **blue** |
| `0x0767` | mode: `0x20` = **latch the colour**, `0x80` = rainbow |
| `0x078c` | status: bits 7-5 = **brightness 0…4**, `0x10` = **latch**, bit 0 = white-only |

Conversion is the driver's own: `level = value * 200 / (255 * 4)` → **0…50**.

These are reached through the raw EC file the driver exposes with
`debugregs=1`, which is root-only:

```
/sys/kernel/debug/qc71_laptop/ec     # offset = EC address, 0x0760..0x078f used here
```

**Proof it is the right place:** before any of this work the registers read
`(0, 50, 50)`, which is exactly `tf_convert_rgb_range` of `(0, 255, 255)` —
the cyan the keyboard was showing.

### Three traps the helper exists to avoid

1. **The colour must be latched.** Writing `0x0769-6b` alone does nothing
   visible; `0x0767` has to be written with `0x20` afterwards. The EC clears
   that bit itself once it has taken the colour, so it must be re-sampled rather
   than cached.
2. **Brightness must be latched too.** Bits 7-5 of `0x078c` only take effect
   when `0x10` is set in the same write. Change them without it and *nothing
   happens* — which is exactly why editing the raw register looks like it
   "does not work".
3. **Never write `0,0,0`.** The EC treats it as "use my defaults" and lights the
   panel itself. Black is therefore the lowest level that holds (`1,1,1`).

### Known limits of this hardware

* **51 colour steps per channel** (0…50), so ~132 k colours rather than 16.7 M.
* **Brightness is 4 steps** (25/50/75/100 %). The field is 3 bits wide but the
  driver caps it at `UNIWILL_KBD_BRIGHTNESS_MAX_1_ZONE_RGB = 0x04`.
* **There is no true "off".** Brightness `0` is rewritten by the EC back to its
  default within ~2 s, and so is the `CTRL_2_SINGLE_COLOR_KBD_BL_OFF` bit in
  `0x078c`. "Off" therefore means *darkest achievable* (`1,1,1` at level 1),
  which the helper reports as `"off":true`.

---

## 3. Quick install

```bash
cd end4-pC/scripts/keyboard-rgb
sudo ./setup-keyboard-rgb.sh                  # defaults: user = whoever ran sudo
sudo ./setup-keyboard-rgb.sh --user dmitriy   # explicit theme user
./setup-keyboard-rgb.sh --check               # verify (works unprivileged)
sudo ./setup-keyboard-rgb.sh --uninstall      # full rollback
```

| # | piece | path |
|---|---|---|
| 1 | helper | `/usr/local/bin/kbd-rgb` (byte-exact from `./kbd-rgb`) |
| 2 | sudoers | `/etc/sudoers.d/zz-kbd-rgb` — NOPASSWD for that one binary |
| 3 | boot unit | `/etc/systemd/system/kbd-rgb-restore.service` |
| 4 | legacy | removes `kbd-backlight-restore.service` (it wrote to a sysfs LED this machine never had) and turns `/usr/local/bin/kbd-backlight-restore.sh` into a delegating shim |
| 5 | module | verifies `qc71_laptop` is loaded with `debugregs=1` |

The sudoers file is named `zz-` on purpose: sudoers uses the **last** matching
entry, so it must sort after any earlier `user ALL=(ALL) ALL`.

---

## 4. Using it

In the shell: **Settings → Keyboard** gives a palette (16 hues × 8 lightness
rows — click a cell to apply it), a brightness slider, a rainbow toggle and
*Match the wallpaper colour*.

Wallpaper matching deliberately reuses the mechanism the shell's dynamic
appearance already runs on rather than sampling the wallpaper itself.
`MaterialThemeLoader` holds a `FileView` with `watchChanges` over the generated
theme file, so when matugen regenerates the palette it rewrites
`Appearance.colors`; the keyboard listens to **that same object** the rest of
the shell follows, which means it changes exactly when, and because, everything
else changes. matugen emits several changes per wallpaper, so those are
debounced, and a write is skipped when the snapped colour has not changed.

Which role of `Appearance.colors` is used is a setting (*Accent role*: primary
active, primary, secondary, tertiary) — the default is `colPrimaryActive`,
because plain `colPrimary` is a tone chosen to sit on a UI surface and reads as
washed out on a keyboard. The followed colour keeps that role's **hue and
lightness** but is taken at **full saturation** (`hardwareColour()`), which is
what the palette's lower rows show. A colour picked by hand is sent as chosen
and turns the switch off, since one option now governs the source.

---

## 5. Troubleshooting

**The page says no device.**
```bash
./setup-keyboard-rgb.sh --check
```
It reports which of `helper`, `sudoers`, `debugregs` or the EC file is missing.
`sudo -n` cannot prompt from a background process, so a missing sudoers rule
shows up as `sudo: a password is required` in the page's error box.

**Inspect the registers directly:**
```bash
sudo -n /usr/local/bin/kbd-rgb dump        # mode / red / green / blue / status
```

**Colours do not change although the registers do.**
Check `modeReg` in `probe`: bit `0x20` must be settable. If the EC clears it
without applying, the colour write raced ahead of it — the helper already writes
colour first, latch second, which is the order the driver uses.

**After a kernel update the helper stops finding the EC file.**
The file only exists with `debugregs=1`. Check
`/etc/modprobe.d/qc71_laptop.conf` still has
`options qc71_laptop debugregs=1` and reboot.

---

## 6. Tests

```bash
bash tests/test_kbd_rgb.sh
```

Hermetic: it injects a synthetic EC image through `KBD_RGB_EC`, so it never
touches hardware and needs no root. It asserts the contract above — one valid
JSON line per call, exit codes, the 0…50 conversion, the 1…4 brightness steps
with their latch, the `0x20` colour latch, black-never-`0,0,0`, rainbow, state
round-trip, and that the installed helper is byte-identical to the repo copy.

Shell-wide: `./tests/run-qml-tests.sh`.
