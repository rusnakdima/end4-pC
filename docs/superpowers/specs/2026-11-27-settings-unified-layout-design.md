# Unified Settings Layout Design

> Status: proposed — awaiting approval. This supersedes the separate
> `categories` style experiment as the direction for Settings navigation.

## Intent and why

The current Settings shell has four visual styles, and the newest `categories`
style regressed controls that the original shell had. Nav items are packed at
the top now, but both side panes keep a fixed width and squeeze/clip the
content pane when the window narrows. There are no expand/collapse controls,
and the only adaptive rule is a single breakpoint that hides the page list.

The user wants one Settings format that combines:
- Windows 11 visual language: compact top toolbar, rounded themed surfaces,
  consistent dividers, predictable spacing.
- Windows/macOS navigation: two independently collapsible side panels
  (categories + pages) beside a content pane.
- Android navigation: on narrow windows, a single content pane with back and
  breadcrumb, with panels reachable through a toggle.

## Goals

1. One adaptive shell renders for every existing `settings.style` value.
2. Restore expand/collapse controls for both side panels.
3. Restore “Collapse all” / “Expand all” for page sections on the open page.
4. Keep a visible search field in every layout; search results must not push
   nav items around.
5. The content pane must never be clipped by side-pane widths; it must be able
   to shrink, with explicit minimums and automatic panel collapse.
6. All colors come from `Appearance` tokens; contrast must hold in both dark
   and light schemes.
7. All existing Settings pages keep working unchanged.

## Non-goals

- Rewriting individual Settings pages (`pages/*.qml`).
- Changing Wi-Fi, Bluetooth, default apps, or keybind behavior.
- Adding new themes or replacing the M3 palette with a separate hardcoded
  palette.
- Google Tasks (explicitly excluded earlier).

## Builder-check rulings (2026-11-27)

These were decided during implementation; they are recorded here so the plan and tests match the shipped behaviour.

1. Dashboard stays a separate window for the `dashboard` style value. Its Home/Media/Presets/Wallpapers pages have no equivalents in `SettingsPages.qml`, so porting them is out of scope; the unified shell covers `default`, `minimal`, and `categories`. Cost: one style remains visually distinct.
2. `SettingsContent.qml` and `CategoriesSettingsContent.qml` remain untouched compatibility shims for deep-link/tab tests. The unified shell exposes `pages`, flat `currentPage`, and `showingProfile` so `Settings.qml`'s existing Tab handlers keep working. Cost: two navigation models remain in the tree, but no page QML changes.
3. Collapse state is in-memory. `userCategoryCollapsed` / `userPageListCollapsed` are separate from transient `auto*` flags, so widening restores the user's choice and `sidebarDensity` is not written by the new toggles. Cost: panel state resets when Settings closes.
4. Search stays in the top toolbar at every width, including narrow mode; the back/breadcrumb row lives inside the content pane. Cost: slightly less room for the page header on narrow windows.
5. A live `settings.style` change re-applies the density preset through a `Connections` handler, without discarding user collapse choices beyond resetting them to the preset baseline. Cost: switching style while open resets user toggles.

## Approaches considered

### A. Upgrade only the `categories` style

Port the missing toolbar controls and fix the width math in
`CategoriesSettingsContent.qml` only. Leave `default`, `minimal`, and
`dashboard` untouched.

Tradeoff: lowest risk, but it keeps four different layouts. The user asked to
merge into one format, so this does not meet the goal.

### B. Replace all four styles with one shell, remove style names

Delete the style branches and the style option. Everyone gets one layout.

Tradeoff: truly one format, but it breaks saved configs and throws away the
style selector. Unnecessary breakage.

### C. Unified shell with style values as density presets (chosen)

One shell component handles every `settings.style` value. The old values stay
valid and map to layout presets:

| `settings.style` | Meaning in the unified shell |
| --- | --- |
| `default` | both panels expanded, comfortable row height |
| `categories` | both panels expanded, comfortable row height (recommended default) |
| `minimal` | category rail icon-only, page list expanded, compact row height |
| `dashboard` | category rail expanded, page list collapsed by default |

Tradeoff: the old dashboard card look is not preserved, but config values keep
working and there is only one navigation format. This is the smallest change
that satisfies “one format” without hard-breaking configs.

## Decisions and how it will work

### Single shell

Create `modules/ii/settings/UnifiedSettingsContent.qml` as the only Settings
shell. `modules/ii/settings/Settings.qml` loads it for every style. Keep
`SettingsContent.qml` and `CategoriesSettingsContent.qml` on disk as thin
compatibility shims that forward to the unified component, so existing deep
links and tests that instantiate them by name keep working. No page QML is
edited.

The shell exposes the same testability aliases already used by
`tst_categories_settings.qml`, plus aliases for the new toolbar buttons and
the two panel rectangles. The hosted harness cannot use `findChild`, so these
aliases are required.

### Layout regions and adaptive rules

The shell is a `RowLayout` with three regions:

1. Category rail (`categoryListRectangle`)
2. Page list (`pageListRectangle`)
3. Content pane (`contentPane`)

State:
- `categoryCollapsed` and `pageListCollapsed` are user-controlled booleans,
  initialized from the style preset.
- `narrow: width < 700`, `medium: width < 1000`.
- Effective visibility:
  - Category rail visible when `!categoryCollapsed` and (`!narrow` or the
    category drawer is open).
  - Page list visible when `!pageListCollapsed` and `!narrow` and no page is
    open. On medium widths, opening a page collapses the page list
    automatically.
  - Content pane always visible; on narrow windows it fills the shell.

Width correctness:
- Side panes use `Layout.preferredWidth` (180 / 240), not fixed widths.
- Both side panes and the content pane set `Layout.minimumWidth: 0`.
- The content Rectangle and its Loader set `implicitWidth: 0`, so the layout
  can shrink them instead of clipping.
- A `minimumContentWidth` of 360 is enforced by auto-collapsing the page list
  first, then the category rail, before the content would fall below it.
- Tests assert content x/width at 1200, 900, 700, and 520 px: content must stay
  inside the shell bounds, never clipped, and panels must collapse in order.

### Toolbar controls

Port the toolbar from `SettingsContent.qml` into the unified shell header:
- `left_panel_open` / `left_panel_close` toggles the category rail collapse.
- A second panel toggle for the page list, using `right_panel_open` /
  `right_panel_close` (or the closest available Material Symbol).
- Visible search field with ArrowUp/ArrowDown/Escape handling and
  `onAccepted: settingsSearch.acceptCurrent()`.
- `unfold_less` → collapse all page sections; `unfold_more` → expand all.
  Reuse the existing `pageSectionIds()` / `setPageSectionsCollapsed()` logic
  against `GlobalStates.currentPageInstance` and
  `Config.options.settings.collapsedSections`.
- On narrow windows, a back button and breadcrumb (`category › page`) replace
  the dual-panel toolbar, matching Android behavior.

Search results remain an overlay anchored under the field, so they never
change nav-item positions.

### Styling

Use only existing `Appearance` tokens:
- category rail `colLayer1`, page list `colLayer0`, content transparent.
- Selected category `colPrimaryContainer`, selected page
  `colSecondaryContainer`.
- 1px dividers between panes, 8px spacing grid, rounded corners from
  `Appearance.rounding`.
- No `colSurface` (it does not exist and previously produced a white pane).

Tests keep the WCAG contrast checks for dark and light schemes and add checks
that nav surfaces follow the active scheme.

### Deep links and key capture

`GlobalStates.settingsTarget` is consumed both in `Component.onCompleted` and
via `Connections`, so cold opens work. `openPage()` updates
`GlobalStates.currentPageInstance` for key-capture pages; clearing the
selection clears the instance.

## Constraints

- Repo: `/mnt/Other/THEMES/end4-pC`, branch `main`.
- Do not touch unrelated user edits in `install.sh`, `sync.sh`,
  `scripts/sddm/`, or SDDM tests.
- Deploy through targeted file copy plus
  `qs -c end4-pC ipc call wallpapers reloadShell`; do not run the
  user-modified `sync.sh`.
- Hosted QML tests require `XDG_CURRENT_DESKTOP=Hyprland` and
  `XDG_SESSION_DESKTOP=hyprland`.
- Pre-existing unrelated `tst_translation.qml` failure stays reported, not
  fixed.

## What is left to the builder

- Exact icon names for the second panel toggle, chosen from symbols already
  used in the repo.
- Exact preset row heights and spacing values, chosen from existing
  `Appearance` tokens and kept consistent across presets.
- Whether the compatibility shims are kept as files or replaced by aliases in
  `Settings.qml`, whichever keeps the hosted tests green with less duplication.

## Acceptance checks

- `tests/shell-tests/tst_categories_settings.qml` extended with:
  toolbar controls present, panel toggles change visibility, width tests at
  1200/900/700/520 px, narrow back/breadcrumb, dark/light contrast.
- `bash tests/qml-compile-check.sh` passes on changed QML.
- Hosted suite with Hyprland env vars: only the pre-existing
  `tst_translation.qml` failure remains.
- `python3 -m unittest discover -s tests -p 'test_*.py'` stays green.
