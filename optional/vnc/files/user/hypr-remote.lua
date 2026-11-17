-- Hidden remote Hyprland instance on the VKMS virtual DRM output.
local home = os.getenv("HOME") or "@HOME@"
HOME = home

-- Load the same end4-pC configuration as the physical session.
dofile(home .. "/.config/hypr/hyprland.lua")

hl.monitor({
    output   = "@HIDDEN_OUTPUT@",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
})

hl.on("hyprland.start", function()
    -- Start the end4-pC shell if the host config did not already do so.
    hl.exec_cmd("sh -c 'sleep 5; pgrep -x qs >/dev/null || exec qs -p @HOME@/.config/quickshell/end4-pC'")
    -- Ensure a terminal is available in the hidden session.
    hl.exec_cmd("sh -c 'sleep 2; exec kitty'")
end)
