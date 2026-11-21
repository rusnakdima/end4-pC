hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Middle button, no modifier: move window with mouse alone
hl.bind("mouse:274", hl.dsp.window.drag(), { mouse = true, description = "Window: Move (mouse only)" })


-- >>> end4-pC managed keybinds >>>
--##! Apps
-- panel-id: mwk50am976iy
hl.bind("CTRL + SUPER + M", hl.dsp.exec_cmd("youtube-music"), {description = "YTM"})
-- <<< end4-pC managed keybinds <<<

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
--#/# bind = SUPER+SHIFT, I,, -- Image Preview: view a file or clipboard image --
hl.bind("SUPER + SHIFT + I", hl.dsp.global("quickshell:imagePreview"), {description = "Utilities: Image preview"})
-- <<< end4-pC utilities keybinds

-- >>> end4-pC advanced-paste window rule (managed by end4-pC)
-- Keep Advanced Paste as a normal floating window with the theme's rounding.
hl.window_rule({ match = { class = "org.quickshell", title = "Advanced Paste" }, float = true, rounding = 18 })
-- <<< end4-pC advanced-paste window rule

-- >>> end4-pC image-preview window rule (managed by end4-pC)
-- Keep the image preview overlay floating with the theme's rounding.
hl.window_rule({ match = { class = "org.quickshell", title = "Image Preview" }, float = true, rounding = 18 })
-- <<< end4-pC image-preview window rule

-- >>> end4-pC tap-super launcher keybinds (managed by end4-pC)
-- Tap Super alone opens the launcher; Super + <key> must not.
--
-- Hyprland 0.57.2's Lua `release = true` binds never fire, and its
-- `hl.dsp.exec_cmd()` dispatcher is a no-op, so neither the classic
-- release bind nor its exec command can open the launcher at all.
-- Detect a real tap from key state instead: a Lua hook marks Super going
-- down and notes any other key pressed while it is held; a repeating
-- timer watches for Super coming back up and dispatches the global
-- shortcut only when it was a genuine tap. 133/134 are Super_L/Super_R
-- in Hyprland's keycode space (evdev code + 8).
--
-- Unbind first so an inherited (possibly global) bind on the same key
-- cannot double-toggle the launcher.
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER + SUPER_R")
local end4pcSuperWasDown = false
local end4pcSuperCombo = false
local function end4pcSuperDown()
    return hl.is_key_down(133) or hl.is_key_down(134)
end
local function end4pcOtherKeyDown()
    for c = 8, 255 do
        if c ~= 133 and c ~= 134 and hl.is_key_down(c) then return true end
    end
    return false
end
hl.on("input.keyboard.key", function()
    if end4pcSuperDown() then
        if not end4pcSuperWasDown then
            end4pcSuperWasDown = true
            end4pcSuperCombo = false
        end
        if end4pcOtherKeyDown() then end4pcSuperCombo = true end
    end
end)
hl.timer(function()
    if not end4pcSuperWasDown then return end
    if end4pcSuperDown() then
        if end4pcOtherKeyDown() then end4pcSuperCombo = true end
        return
    end
    end4pcSuperWasDown = false
    if not end4pcSuperCombo then
        hl.dispatch(hl.dsp.global("quickshell:searchToggle"))
    end
end, { timeout = 30, type = "repeat" })
-- <<< end4-pC tap-super launcher keybinds
