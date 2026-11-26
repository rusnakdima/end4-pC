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
--#/# bind = ALT, Space,, -- Peek: preview the current selection or file --
hl.bind("ALT + SPACE", hl.dsp.global("quickshell:peek"), {description = "Utilities: Peek preview"})
--#/# bind = SUPER+SHIFT, Space,, -- Peek preview fallback --
hl.bind("SUPER + SHIFT + SPACE", hl.dsp.global("quickshell:peek"), {description = "Utilities: Peek preview"})
-- <<< end4-pC utilities keybinds

-- >>> end4-pC advanced-paste window rule (managed by end4-pC)
-- Keep Advanced Paste as a normal floating window with the theme's rounding.
hl.window_rule({ match = { class = "org.quickshell", title = "Advanced Paste" }, float = true, rounding = 18 })
-- <<< end4-pC advanced-paste window rule

-- >>> end4-pC image-preview window rule (managed by end4-pC)
-- Keep the image preview overlay floating with the theme's rounding.
hl.window_rule({ match = { class = "org.quickshell", title = "Image Preview" }, float = true, rounding = 18 })
-- <<< end4-pC image-preview window rule

-- >>> end4-pC peek window rules (managed by end4-pC)
-- Keep Peek floating with the theme's rounding; the nvim editor launched by
-- Peek opens as a floating terminal so the selected text stays readable.
hl.window_rule({ match = { class = "org.quickshell", title = "Peek" }, float = true, rounding = 18 })
hl.window_rule({ match = { title = "end4-pc-peek" }, float = true, size = "1100 700" })
-- <<< end4-pC peek window rules

-- >>> end4-pC tap-super launcher keybinds (managed by end4-pC)
-- Tap Super alone opens the launcher; Super + <key> must not.
--
-- Hyprland 0.57.2's Lua `release = true` binds never fire and `hl.dsp.exec_cmd()`
-- is a no-op, so detect a tap from the `input.keyboard.key` event stream: each
-- event carries the keycode, a millisecond timestamp and the press/release
-- state. A tap is a short, uninterrupted Super press. A mouse click while Super
-- is held is invisible to Lua, but holding Super to click takes much longer
-- than a tap, so the duration gate suppresses the launcher in that case.
--
-- Unbind first so an inherited (possibly global) bind on the same key
-- cannot double-toggle the launcher.
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER + SUPER_R")
local end4pcSuperTapMs = 350
local end4pcSuperPressAt = 0
local end4pcSuperCombo = false
local function end4pcOtherKeyDown()
    for c = 8, 255 do
        if c ~= 133 and c ~= 134 and hl.is_key_down(c) then return true end
    end
    return false
end
hl.on("input.keyboard.key", function(code, ts, state)
    if code == 133 or code == 134 then
        if state == 1 then
            -- Super pressed: start timing a potential tap.
            end4pcSuperPressAt = ts
            end4pcSuperCombo = end4pcOtherKeyDown()
        elseif state == 0 and end4pcSuperPressAt ~= 0 then
            -- Super released: commit only a short, uninterrupted tap.
            local held = ts - end4pcSuperPressAt
            if not end4pcSuperCombo and not end4pcOtherKeyDown() and held <= end4pcSuperTapMs then
                hl.dispatch(hl.dsp.global("quickshell:searchToggle"))
            end
            end4pcSuperPressAt = 0
            end4pcSuperCombo = false
        end
    elseif end4pcSuperPressAt ~= 0 and state == 1 then
        -- Another key pressed while Super is held: a combo, not a tap.
        end4pcSuperCombo = true
    end
end)
-- <<< end4-pC tap-super launcher keybinds
