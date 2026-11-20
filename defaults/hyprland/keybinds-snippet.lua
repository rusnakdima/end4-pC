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

-- >>> end4-pC utilities keybinds (managed by end4-pC)
--##! Utilities
--#/# bind = SUPER+SHIFT, V,, -- Advanced Paste: paste clipboard in another format --
hl.bind("SUPER + SHIFT + V", hl.dsp.global("quickshell:advancedPaste"), {description = "Utilities: Advanced Paste"})
--#/# bind = SUPER+SHIFT, F,, -- Find My Mouse: highlight the pointer --
hl.bind("SUPER + SHIFT + F", hl.dsp.global("quickshell:findMouse"), {description = "Utilities: Find My Mouse"})
--#/# bind = SUPER+SHIFT, U,, -- Toggle the on-screen ruler --
hl.bind("SUPER + SHIFT + U", hl.dsp.global("quickshell:screenRuler"), {description = "Utilities: Screen ruler"})
-- <<< end4-pC utilities keybinds

-- >>> end4-pC advanced-paste window rule (managed by end4-pC)
-- Keep Advanced Paste as a normal floating window with the theme's rounding.
hl.window_rule({ match = { class = "org.quickshell", title = "Advanced Paste" }, float = true, rounding = 18 })
-- <<< end4-pC advanced-paste window rule
