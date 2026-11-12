-- >>> waydroid-autostart (managed by end4-pC optional/waydroid)
-- Waydroid: start Android session on login (safe if already running)
hl.on("hyprland.start", function ()
    hl.exec_cmd("waydroid session start")
end)
-- <<< waydroid-autostart
