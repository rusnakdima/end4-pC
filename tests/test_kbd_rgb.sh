#!/usr/bin/env bash
#
# Regression test for the keyboard RGB helper (scripts/keyboard-rgb/kbd-rgb).
#
# The helper writes a real EC through debugfs, which only exists as root on
# real hardware, so every case runs against a synthetic EC image injected with
# KBD_RGB_EC. That keeps the test hermetic and pins down the contract the shell
# depends on:
#
#   * exactly one line of valid JSON on stdout, whatever happens
#   * exit 0 on success, 1 on a rejected argument or a failed write
#   * colour converted with the driver's own formula, 0..255 -> 0..50
#   * brightness clamped to levels 1..4 (level 0 is rejected by the EC), held
#     in bits 7-5 of 0x078c with the 0x10 latch set
#   * the colour latch 0x20 is set in mode 0x0767
#   * "off" is the darkest state that holds (1 per channel at level 1), because
#     the EC rejects both brightness 0 and rewrites 0,0,0 with its own default
#
# Run:  bash tests/test_kbd_rgb.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$SCRIPT_DIR/scripts/keyboard-rgb/kbd-rgb"

fail=0
say() { printf '  %s\n' "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

[[ -x "$HELPER" ]] || { echo "FAIL: $HELPER missing or not executable" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not installed"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Register offsets, mirroring the helper.
M_RGB_MODE=1895   # 0x0767
M_R=1897          # 0x0769
M_G=1898          # 0x076a
M_B=1899          # 0x076b
M_STATUS=1932     # 0x078c
EC_SIZE=2048      # must cover 0x078f

EC_FILE="$WORK/ec"
STATE="$WORK/state"

reset_ec() {
    # A sparse file of zeros: a clean EC image.
    truncate -s "$EC_SIZE" "$EC_FILE"
    rm -f "$STATE"
    # The firmware's starting point on this machine: cyan at brightness 1.
    poke "$M_R" 0
    poke "$M_G" 50
    poke "$M_B" 50
    poke "$M_STATUS" 32
}

export KBD_RGB_EC="$EC_FILE"
export KBD_RGB_STATE="$STATE"

poke() { printf '%b' "$(printf '\\x%02x' "$2")" | dd of="$EC_FILE" bs=1 seek="$1" conv=notrunc 2>/dev/null; }
peek() { dd if="$EC_FILE" bs=1 skip="$1" count=1 2>/dev/null | od -An -tu1 | tr -d ' \n'; }

run() { # <expected exit 0|1> <helper args...>
    local want="$1"; shift
    OUT="$("$HELPER" "$@" 2>&1)"
    local rc=$?
    if [ "$rc" -ne "$want" ]; then
        die "$*: expected exit $want, got $rc ($OUT)"
        return 1
    fi
    if ! printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, dict)' 2>/dev/null; then
        die "$*: stdout is not one valid JSON object: $OUT"
        return 1
    fi
    case "$OUT" in
        *$'\n'*) die "$*: printed more than one line: $OUT"; return 1 ;;
    esac
    return 0
}

field() { # <json key> -> value in $VAL (booleans spelled lowercase, as JSON)
    VAL="$(printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
v = d.get(sys.argv[1])
if v is None:
    print("")
elif isinstance(v, bool):          # before int: bool subclasses int in Python
    print("true" if v else "false")
elif isinstance(v, (str, int, float)):
    print(v)
else:
    print(json.dumps(v))
' "$1")"
}

status_level() { printf '%d' $(( ( $(peek $M_STATUS) >> 5 ) & 0x07 )); }

# ---------------------------------------------------------------------------
echo "test: a missing EC image is a clean error, not a crash"
reset_ec
KBD_RGB_EC="$WORK/nowhere" run 1 probe
field error
[ -n "$VAL" ] || die "probe with no EC file reported no error"
say "probe with no EC file: $VAL"
KBD_RGB_EC="$EC_FILE"

# ---------------------------------------------------------------------------
echo "test: probe reports the firmware's starting state"
reset_ec
run 0 probe
field available;     [ "$VAL" = "true" ]  || die "available=$VAL"
field backend;       [ "$VAL" = "ec" ]     || die "backend=$VAL"
field color;         [ "$VAL" = "#00ffff" ] || die "color=$VAL, expected #00ffff"
field brightness;    [ "$VAL" = "25" ]     || die "brightness=$VAL, expected 25"
field whiteOnly;     [ "$VAL" = "false" ]  || die "whiteOnly=$VAL"
say "probe: $OUT"

# ---------------------------------------------------------------------------
echo "test: colour is converted with the driver's own formula (0..255 -> 0..50)"
reset_ec
run 0 set --color "#ff9800" --brightness 100
[ "$(peek $M_R)" -eq 50 ] || die "red=$(peek $M_R), expected 50"
[ "$(peek $M_G)" -eq 29 ] || die "green=$(peek $M_G), expected 29"
[ "$(peek $M_B)" -eq 0  ] || die "blue=$(peek $M_B), expected 0"
# 0x20 = apply-colour latch must be set in mode.
[ $(( $(peek $M_RGB_MODE) & 0x20 )) -ne 0 ] || die "colour latch 0x20 not set (mode=$(peek $M_RGB_MODE))"
# probe must report the closest achievable colour, so the UI preview cannot
# disagree with the panel.
run 0 probe
field color; [ "$VAL" = "#ff9400" ] || die "snapped colour=$VAL, expected #ff9400"
say "#ff9800 -> EC (50,29,0), snapped preview #ff9400"

# ---------------------------------------------------------------------------
echo "test: brightness maps onto levels 1..4 with the latch set"
reset_ec
# Only the four exact steps round-trip; anything between them lands on the
# nearest level, which is the hardware's whole granularity.
for pair in "100 4" "75 3" "50 2" "25 1"; do
    set -- $pair
    run 0 set --color "#ffffff" --brightness "$1"
    [ "$(status_level)" -eq "$2" ] || die "${1}% -> level $(status_level), expected $2"
    [ $(( $(peek $M_STATUS) & 0x10 )) -ne 0 ] || die "latch 0x10 not set at ${1}%"
    run 0 probe
    field brightness; [ "$VAL" = "$1" ] || die "probe brightness=$VAL after setting $1%"
done
say "25/50/75/100% round-trip as levels 1/2/3/4"

echo "test: values between steps snap to the nearest level"
reset_ec
run 0 set --color "#ffffff" --brightness 60
[ "$(status_level)" -eq 2 ] || die "60% -> level $(status_level), expected 2"
run 0 set --color "#ffffff" --brightness 1
[ "$(status_level)" -eq 1 ] || die "1% -> level $(status_level), expected 1 (never 0)"
say "60% -> level 2, 1% -> level 1"

# ---------------------------------------------------------------------------
echo "test: level 0 is never written (the EC rejects it)"
reset_ec
run 0 set --color "#ffffff" --brightness 0
[ "$(status_level)" -ne 0 ] || die "brightness 0 wrote level 0, which the EC ignores"
say "minimum level is $(status_level), not 0"

# ---------------------------------------------------------------------------
echo "test: off drives the darkest state the panel will hold"
reset_ec
run 0 set --color "#ff0000" --brightness 100
run 0 off
[ "$(peek $M_R)" -eq 1 ] || die "off left red=$(peek $M_R), expected 1"
[ "$(peek $M_G)" -eq 1 ] || die "off left green=$(peek $M_G), expected 1"
[ "$(peek $M_B)" -eq 1 ] || die "off left blue=$(peek $M_B), expected 1"
[ "$(status_level)" -eq 1 ] || die "off wrote brightness level $(status_level), expected 1"
run 0 probe
field off; [ "$VAL" = "true" ] || die "probe did not report off"
field brightness; [ "$VAL" = "0" ] || die "probe reports brightness=$VAL while off"
say "off = (1,1,1) at level 1; probe reports off:true and brightness 0"

echo "test: a black colour maps to the darkest level, never 0,0,0"
reset_ec
run 0 set --color "#ff9800" --brightness 100
run 0 set --color "#000000" --brightness 100
[ "$(peek $M_R)" = "1" ] && [ "$(peek $M_G)" = "1" ] && [ "$(peek $M_B)" = "1" ] \
    || die "black gave $(peek $M_R) $(peek $M_G) $(peek $M_B), expected 1 1 1 (0,0,0 would trigger the EC default)"
run 0 probe
field off; [ "$VAL" = "true" ] || die "probe did not report off for black"
say "black -> (1,1,1), never 0,0,0"

# ---------------------------------------------------------------------------
echo "test: rainbow mode sets bit 7 and skips the colour latch"
reset_ec
run 0 set --color "#ff0000" --brightness 100 --mode rainbow
[ $(( $(peek $M_RGB_MODE) & 0x80 )) -ne 0 ] || die "rainbow bit not set (mode=$(peek $M_RGB_MODE))"
run 0 probe
field mode; [ "$VAL" = "rainbow" ] || die "probe mode=$VAL"
say "rainbow holds"

echo "test: leaving rainbow returns to static"
run 0 set --color "#ff0000" --mode static
[ $(( $(peek $M_RGB_MODE) & 0x80 )) -eq 0 ] || die "rainbow bit still set"
say "static clears it"

# ---------------------------------------------------------------------------
echo "test: bad arguments are rejected with exit 1 and an explanation"
reset_ec
BEFORE=$(peek $M_STATUS)
run 1 set --color "red";                 field error; [ -n "$VAL" ] || die "no error for 'red'"
run 1 set --color "#abc";                field error; [ -n "$VAL" ] || die "no error for '#abc'"
run 1 set --color "#gg0000";             field error; [ -n "$VAL" ] || die "no error for '#gg0000'"
run 1 set --color "#ff0000" --mode fast; field error; [ -n "$VAL" ] || die "no error for bad mode"
run 1 set --color "#ff0000" --brightness high; field error; [ -n "$VAL" ] || die "no error for bad brightness"
run 1 frobnicate;                        field error; [ -n "$VAL" ] || die "no error for unknown command"
[ "$(peek $M_STATUS)" -eq "$BEFORE" ] || die "a rejected call changed the status register"
say "all rejections clean, EC untouched"

# ---------------------------------------------------------------------------
echo "test: state round-trips through save and restore"
reset_ec
run 0 set --color "#4caf50" --brightness 75
R_BEFORE=$(peek $M_R); S_BEFORE=$(peek $M_STATUS)
run 0 restore
[ "$(peek $M_R)" -eq "$R_BEFORE" ] || die "restore did not reproduce the colour"
[ "$(peek $M_STATUS)" -eq "$S_BEFORE" ] || die "restore did not reproduce the status"
run 0 probe
field color; [ "$VAL" = "#47ad4d" ] || die "restored colour=$VAL, expected #47ad4d"
field brightness; [ "$VAL" = "75" ] || die "restored brightness=$VAL, expected 75"
# No state is a no-op, not a failure: the boot unit must not fail on a fresh
# machine.
rm -f "$STATE"
run 0 restore
field restored; [ "$VAL" = "false" ] || die "empty restore said restored=$VAL"
say "state round-trip holds"

# ---------------------------------------------------------------------------
echo "test: the installed helper is byte-identical to the repo copy"
if [ -x /usr/local/bin/kbd-rgb ]; then
    cmp -s "$HELPER" /usr/local/bin/kbd-rgb \
        && say "installed helper matches the repo copy" \
        || die "/usr/local/bin/kbd-rgb differs from scripts/keyboard-rgb/kbd-rgb"
else
    say "not installed (run scripts/keyboard-rgb/setup-keyboard-rgb.sh)"
fi

# ---------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "PASS: kbd-rgb helper contract"
else
    echo "FAIL: $fail check(s) failed" >&2
    exit 1
fi
