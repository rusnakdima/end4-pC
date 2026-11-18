-- >>> end4-pC workspace-follow keybinds (managed by end4-pC)
-- SUPER + SHIFT + <1-0>: send the focused window to workspace N and follow it,
-- i.e. switch to that workspace as well. SUPER + ALT + <1-0> stays the silent
-- variant that leaves the focus where it is.
--
-- The binds use evdev keycodes rather than digits on purpose: while Shift is
-- held the number row reports punctuation ("!" for SHIFT + 1 on us/ru), so a
-- bind on the digit itself would never fire. The codes are 1..9,0.
--##! Window
--#/# bind = SUPER+SHIFT, Hash,, -- Send to workspace and switch -- (1, 2, 3,...)
local workspaceFollowRow = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
for i = 1, 10 do
    hl.bind("SUPER + SHIFT + code:" .. workspaceFollowRow[i], function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = true }))
    end, { description = "Window: Send to workspace " .. i .. " and switch" })
end

-- Numeric keypad, in the same order as the theme's silent-move loop.
local workspaceFollowNumpad = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
for i = 1, 10 do
    hl.bind("SUPER + SHIFT + code:" .. workspaceFollowNumpad[i], function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = true }))
    end, { description = "Window: Send to workspace " .. i .. " and switch" })
end
-- <<< end4-pC workspace-follow keybinds
