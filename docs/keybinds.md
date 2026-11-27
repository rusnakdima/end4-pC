# Keybinds

How Hyprland keybinds are stored, generated and edited in end4-pC.

The frozen catalog plus an optional user overlay are the only inputs. Everything
Hyprland loads, and everything the shell uses to run commands from binds, is
**generated** from them. Settings writes only the overlay — never a generated
Lua file, a `keybind_overrides.conf`, or the catalog. Never edit a generated
file by hand: a later save regenerates it wholesale.

## How the pieces fit together

```
defaults/hyprland/keybinds.json          (frozen catalog — read-only)
~/.config/hypr/custom/keybind-overlay.json  (user changes — written by Settings)
                │
                │  scripts/hyprland/generate_keybinds.py
                │  (run by sync.sh, or by Settings after each save)
                ▼
   ├─ ~/.config/hypr/hyprland/keybinds.lua        binds with source: "main"
   ├─ ~/.config/hypr/custom/keybinds.lua          binds with source: "custom"
   └─ ~/.config/quickshell/end4-pC/state/
         generated-commands.json                  id → { command, description, category }
                │
                │  services/GeneratedCommandShortcuts.qml
                ▼
   quickshell:runCommand:<id>  global shortcuts → bash -lc <command>
```

The generated Lua files are what Hyprland actually loads. The settings page and
the cheatsheet read the same catalog + overlay through
`services/HyprlandKeybinds.qml`, so the displayed list cannot drift from the
bound list.

Two Hyprland 0.57.2 quirks explain the design:

- `hl.dsp.exec_cmd()` is a no-op, so a `command` bind dispatches
  `hl.dsp.global("quickshell:runCommand:<id>")` instead, and the shell runs the
  real command (see [Command bridge](#command-bridge)).
- `release = true` binds never fire, so "tap Super to open the launcher" uses a
  key-state timer on keycodes 133/134 (`Super_L`/`Super_R`) in the generated
  custom preamble, not a release bind.

## Files

| Path | Role | Written by |
|---|---|---|
| `defaults/hyprland/keybinds.json` | Frozen default catalog (207 binds); the single source of truth | Project (committed) |
| `~/.config/hypr/custom/keybind-overlay.json` | User overrides, adds and disabled ids — the only write path | Settings only (via `ManagedKeybinds`) |
| `scripts/hyprland/generate_keybinds.py` | Merges catalog + overlay, renders all three outputs | — |
| `~/.config/hypr/hyprland/keybinds.lua` | Generated main binds | Generator |
| `~/.config/hypr/custom/keybinds.lua` | Generated custom binds (also carries the preamble, including the tap-Super block) | Generator |
| `~/.config/quickshell/end4-pC/state/generated-commands.json` | Command-bridge map used by the shell | Generator |
| `services/GeneratedCommandShortcuts.qml` | Registers one global shortcut per generated id and runs its command | — |
| `services/ManagedKeybinds.qml` | Settings IO: reads/writes the overlay, runs the generator, reloads Hyprland | — |
| `services/HyprlandKeybinds.qml` | Merged, effective bind list for the settings page and cheatsheet | — |
| `services/DisabledKeybinds.qml` | Recoverable delete/restore via `overlay.disabled` (no Lua markers) | — |
| `modules/common/functions/KeybindStore.js` | Overlay parse/render and merge helpers used by Settings | — |
| `scripts/hyprland/get_keybinds.py` | Legacy Lua parser; no longer used at runtime (kept for reference/tests) | — |
| `defaults/hyprland/keybinds.baseline.json` | Frozen id set/counts for drift detection (refresh with `--bless`) | — |
| `scripts/hyprland/validate_keybind_catalog.py` | Validates catalog + optional overlay and generated output | — |
| `sync.sh` | Deploys the tree, then regenerates all keybind outputs | — |

## Catalog fields

Each entry in `defaults/hyprland/keybinds.json` has these fields:

| Field | Meaning |
|---|---|
| `id` | Stable key used by overlay overrides, adds, disabled ids and the command bridge. |
| `source` | `"main"` or `"custom"` — which generated Lua file the bind lands in. |
| `category`, `group` | Cheatsheet grouping (section and sub-heading). |
| `combo` | Hyprland key string, e.g. `"SUPER + Tab"`. |
| `description`, `label` | Human-readable label shown in the cheatsheet and settings. |
| `options` | Flags forwarded to `hl.bind` (`release`, `locked`, `repeat`, `mouse`, …). |
| `dispatch` | Normalized action spec — a `kind` plus its argument. Kinds include `command`, `global`, `focus`, `window.*`, `layout` and `raw`. |
| `code` | The literal Lua statement. Emitted verbatim for `raw` binds; for all other kinds the generator rebuilds the statement from `combo` + `dispatch` + `options`. |
| `line` | Source line recorded when the catalog was extracted; bookkeeping only, not used at runtime. |

So: edit `dispatch`, not `code`, for a non-`raw` bind; a `raw` bind is opaque and
its `code` is preserved as-is.

## Overlay format

`~/.config/hypr/custom/keybind-overlay.json` holds only user changes. The
generator never writes it. A missing overlay is the normal case (defaults only).

```json
{
  "overrides": {
    "bind-3": { "combo": "SUPER + GRAVE" }
  },
  "adds": [
    {
      "id": "my-terminal",
      "category": "Apps",
      "combo": "SUPER + ALT + T",
      "description": "My terminal",
      "dispatch": { "kind": "command", "id": "my-terminal", "command": "foot" },
      "options": {},
      "source": "custom",
      "code": "hl.bind(\"SUPER + ALT + T\", hl.dsp.exec_cmd(\"foot\"), { description = \"My terminal\" })"
    }
  ],
  "disabled": ["screen"]
}
```

- `overrides`: keyed by catalog `id`. Editable fields are `combo`,
  `description`, `category`, `dispatch` and `options`; `enabled: false` also
  drops the bind. A command bind's `dispatch` stays with the catalog.
- `adds`: new binds. Give each a unique `id`; for a command bind set
  `dispatch.kind` to `"command"` and `dispatch.id` to the same `id` — that id
  becomes a `generated-commands.json` entry. `code` is the legacy-mode fallback
  statement.
- `disabled`: catalog ids to omit entirely from the generated output. Settings'
  *Delete* action adds ids here through `ManagedKeybinds.disable()`; *Restore*
  removes them with `enable()`. No comment markers are written to Lua.

For a normal edit, prefer the Settings UI over hand-writing this file.

## Add, change or disable a bind from Settings

Settings → **Keyboard**:

- **Add** — the Keybind manager form takes a name, category, command and a
  captured combination. `ManagedKeybinds.create()` stores it as an overlay
  `adds` entry (`KeybindStore.makeAdd`).
- **Change** — editing one of the panel's adds rewrites that `adds` entry.
  Rebinding a catalog (theme) bind — from a row or a conflict move — writes
  `overrides[id].combo` through `ManagedKeybinds` (`setOverride()` /
  `update()`); the catalog's dispatch and options stay frozen. A `raw` bind
  (76 of the 207 defaults) emits its Lua verbatim, so its keys are not
  editable in Settings and its combo override is refused.
- **Disable / delete** — `services/DisabledKeybinds.qml` maps the row's delete
  id to its catalog ids and calls `ManagedKeybinds.disable()`, which appends
  them to `overlay.disabled`. The bind disappears from the generated Lua on
  the next regeneration; **Restore** calls `enable()` to remove them. Because
  the ids live in the overlay, a later create/rebind/save cannot resurrect a
  deleted bind.

Every Settings save goes through the same chain: write the overlay → run
`generate_keybinds.py` (same contract as `sync.sh`) → `hyprctl reload`. The
generator rewrites the Lua files and the command bridge wholesale, so the
overlay stays the only file Settings modifies for add/change/delete. The
legacy `keybind_overrides.conf` and Lua comment markers are not part of this
contract and are ignored by the generator.

## Default apps

The **Default apps** page (Settings → General) is a shortcut for choosing the
app behind the bundled launch binds. It covers the eight roles whose catalog
command is a fallback chain — terminal, file manager, browser, code editor,
office, text editor, volume mixer and task manager — and never writes XDG or
`mimeapps.list` files: the system's MIME defaults are untouched.

For each role the page lists the apps matching that role (from installed
`.desktop` entries, with a "Show all applications" switch), plus a combo editor
and a reset button. Saving writes `overrides[id].dispatch.command` for every
bind id of that role through `ManagedKeybinds.updateCatalogBind()`, then follows
the same write → regenerate → reload chain as the Keybind page. Terminal's three
binds (`apps`, `apps-2`, `apps-3`) move together. Resetting calls
`clearOverride()` on those ids and restores the frozen fallback chain. Because
the override is the only persisted state, a chosen app and its shortcut stay in
one place: `~/.config/hypr/custom/keybind-overlay.json`. The catalog ids
`apps-10` (Settings), `apps-12` (window resize) and `apps-13` (YouTube Music,
a custom-sourced bind) are intentionally not part of the page.

## Command bridge

Because `hl.dsp.exec_cmd()` does nothing on Hyprland 0.57.2, a `command` bind is
generated as:

```lua
hl.bind("SUPER + ALT + T", hl.dsp.global("quickshell:runCommand:my-terminal"), { description = "My terminal" })
```

and the generator writes `"my-terminal": { "command": "foot", ... }` into
`generated-commands.json`. `GeneratedCommandShortcuts.qml` watches that file,
registers a `GlobalShortcut` named `runCommand:<id>` (the protocol adds the
`quickshell:` appid prefix), and on press runs `bash -lc <command>` with `$HOME`
and `$qsConfig` expanded. Unknown ids are refused. Ids come only from the JSON,
and the file is re-read on change and every 5 s, so adding or removing a command
while the shell is running needs no restart.

## Deployment with `sync.sh`

- `./sync.sh` — full deploy; after tree sync and restoring user edits it calls
  the generator, so a restored user edit cannot shadow the generated files.
  The old managed-block injector is deliberately not run here — the generated
  `custom/keybinds.lua` already carries every bind.
- `./sync.sh --keybinds-only` — skips the tree sync, only regenerates the
  keybind Lua files and command bridge.
- `./sync.sh --dry-run` (`-n`) — reports the catalog/overlay and the three would-be
  output paths and writes nothing. Safe while another lane is testing live binds.
- `./sync.sh --user NAME` (or `--user=NAME`) — target another user. Both spellings
  work; an unknown user or a missing value exits with status 2 before any writes.
  Run `./sync.sh --help` for the full option list and exit codes.
- The overlay is opt-in: it is passed to the generator only if the file exists,
  and is never modified. When sync runs as root, the generated files are chowned
  back to the target user.

## Default apps

The Default apps pane and the Keyboard pane write the same files described
above — no separate settings store:

- Built-in roles (terminal, file manager, browser, code editor, office, text
  editor, volume mixer, task manager) are listed in `defaults/default-apps.json`.
  Each role names its frozen catalog bind ids; picking an app writes narrow
  overrides for those ids and the reset button clears them.
- An app added with **Add app** is an `adds` entry in
  `~/.config/hypr/custom/keybind-overlay.json` with `category: "Apps"`, a
  `combo`, and a `command` dispatch. Its icon is looked up from the command, so
  no icon field is stored in the JSON. The delete button removes the add.
- Both panes can change an app's keybind. Changing it in Default apps writes
  overrides for built-in ids or edits the add in place; changing it in Keyboard
  uses the same overlay through the normal form. After a save the generator
  regenerates the Lua/command bridge and Hyprland reloads, so the two panes
  stay in sync.

## Validation

Use temporary outputs; do not run these against live paths while other lanes are
testing live binds.

```sh
python3 -m json.tool defaults/hyprland/keybinds.json >/dev/null          # catalog is valid JSON

python3 scripts/hyprland/generate_keybinds.py \
    --catalog defaults/hyprland/keybinds.json \
    --main-out /tmp/opencode/keybinds-main.lua \
    --custom-out /tmp/opencode/keybinds-custom.lua \
    --commands-out /tmp/opencode/generated-commands.json

luac -p /tmp/opencode/keybinds-main.lua /tmp/opencode/keybinds-custom.lua  # generated Lua parses

python3 scripts/hyprland/validate_keybind_catalog.py                     # frozen catalog checks
python3 scripts/hyprland/validate_keybind_catalog.py --overlay <file>     # also validate an overlay

./sync.sh --keybinds-only --dry-run                                      # deploy plan, writes nothing
```

`validate_keybind_catalog.py` compares the id list, counts, and duplicate
combos against the frozen baseline in `defaults/hyprland/keybinds.baseline.json`
(never edited by hand during normal work). When intentionally changing the
frozen set — adding/removing a default bind, renaming an id — refresh that
baseline with `python3 scripts/hyprland/validate_keybind_catalog.py --bless`.
With `--overlay`, it also validates the overlay (fail-fast on unknown ids,
duplicate ids, bad combos, missing/invalid dispatch, conflicting command ids)
and checks the generated Lua + `generated-commands.json` for parity.

Pass `--overlay <file>` to the generator (using a **temp copy**) to validate a
specific overlay. Useful checks beyond the commands above: the generator prints
`generated <N> binds; <M> command bridges`, `generated-commands.json` must be
parseable with `python3 -m json.tool`, `hyprctl binds -j` shows the loaded binds
after a reload. (`scripts/hyprland/get_keybinds.py` is a legacy Lua parser that
is no longer used at runtime: the settings page and cheatsheet read the JSON
catalog + overlay directly via `services/HyprlandKeybinds.qml`.)
