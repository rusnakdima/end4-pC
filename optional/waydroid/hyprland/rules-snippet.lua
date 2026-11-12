-- >>> waydroid-rules (managed by end4-pC optional/waydroid)
-- Android app windows (persist.waydroid.multi_windows=true): one phone-shaped
-- floating card per app. Class is the package name, e.g. waydroid.com.android.calculator2.
hl.window_rule({
    match = { class = "^waydroid\\." },
    float = true,
    size = { 420, 760 },
    center = true,
})

-- The full Android UI window (waydroid show-full-ui) uses class "Waydroid".
hl.window_rule({
    match = { class = "^Waydroid$" },
    float = true,
})
-- <<< waydroid-rules
