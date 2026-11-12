-- >>> waydroid-keybinds (managed by end4-pC optional/waydroid)
-- SUPER+CTRL+A: whole Android desktop in one window
hl.bind("SUPER + CTRL + A", hl.dsp.exec_cmd("waydroid show-full-ui"),
    { description = "App: Show full Waydroid UI" })

-- SUPER+CTRL+SHIFT+A: regenerate .desktop entries for installed Android apps
hl.bind("SUPER + CTRL + SHIFT + A",
    hl.dsp.exec_cmd("$HOME/.config/quickshell/$qsConfig/scripts/waydroid-desktop-gen.sh"),
    { description = "App: Regenerate Android desktop entries" })
-- <<< waydroid-keybinds
