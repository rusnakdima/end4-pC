#!/bin/bash
# Restore keyboard RGB backlight from state file at boot.
# Color/brightness come from the state saved by kbd-backlight-x16c(1).
LED="/sys/kernel/debug/qc71_laptop/regs/lightbar_ctrl"
STATE="/var/lib/ambxst/kbd-backlight.state"
if [ -d "$LED" ]; then
    if [ -r "$STATE" ]; then
        r=$(cat "$STATE" | awk '{print $1}')
        g=$(cat "$STATE" | awk '{print $2}')
        b=$(cat "$STATE" | awk '{print $3}')
        printf '0x01\n' > "$LED"
        printf '0x%02x\n' "$r" > /sys/kernel/debug/qc71_laptop/regs/lightbar_red
        printf '0x%02x\n' "$g" > /sys/kernel/debug/qc71_laptop/regs/lightbar_green
        printf '0x%02x\n' "$b" > /sys/kernel/debug/qc71_laptop/regs/lightbar_blue
    fi
    echo "Keyboard: $(cat /sys/kernel/debug/qc71_laptop/regs/lightbar_red | sed 's/^0x//') $(cat /sys/kernel/debug/qc71_laptop/regs/lightbar_green | sed 's/^0x//') $(cat /sys/kernel/debug/qc71_laptop/regs/lightbar_blue | sed 's/^0x//')"
else
    echo "No keyboard backlight device found"
fi