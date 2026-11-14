#!/bin/sh
#
# Superseded by /usr/local/bin/kbd-rgb (scripts/keyboard-rgb).
#
# This path used to hold a second, independently maintained copy of the boot
# restore logic -- and the two had drifted: the installed one wrote to
# /sys/class/leds/rgb:kbd_backlight, a device this machine does not have, so it
# silently did nothing at every boot while the repo copy used the EC registers.
#
# There is now exactly one implementation, in scripts/keyboard-rgb/kbd-rgb, and
# this file is installed byte-exact from the repo so the two cannot diverge
# again. Anything still calling the old name keeps working.
exec /usr/local/bin/kbd-rgb restore
