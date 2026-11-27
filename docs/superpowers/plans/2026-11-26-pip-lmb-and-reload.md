# PiP LMB grab and working theme reload Implementation Plan

> **Superseded (2026-11-27):** The PiP plain-LMB grab described here was removed by user request. Hyprland/browser native hold-LMB-to-move is now the only behavior; see `2026-11-27-pip-lmb-removal.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make plain LMB grab/move the PiP window without breaking LMB elsewhere, and make CTRL+SUPER+R actually reload the live shell.

**Architecture:** Both fixes live in the frozen JSON catalog. The PiP fix appends a Lua preamble block that dynamically binds/unbinds `mouse:272` on `window.active`; the reload fix corrects the raw command of `bind-26`. The generator renders catalog preamble verbatim into the live Lua files, so no QML change is needed.

**Tech Stack:** Hyprland 0.57.2 Lua API (`hl.on("window.active", ...)`, `hl.bind`, `hl.unbind`, `hl.dsp.window.drag()`, `hl.config`), Python generator/validator, unittest.

**Spec:** `docs/superpowers/specs/2026-11-26-pip-lmb-and-reload-design.md`

## Global Constraints

- Never reboot, kill, shutdown, or restart processes without explicit permission.
- The reload bind may be triggered (user explicitly allowed it); no other process stoppage is allowed.
- QML/Lua changes take effect only after the user reloads the shell; do not trigger a reload except when verifying the reload bind itself.
- Live outputs are `/home/dmitriy/.config/hypr/hyprland/keybinds.lua`, `/home/dmitriy/.config/hypr/custom/keybinds.lua`, and `/home/dmitriy/.config/quickshell/end4-pC/state/generated-commands.json`.
- Keep `SUPER+LMB`, `SUPER+RMB`, and MMB drag unchanged.
- Do not add a global plain-LMB drag; it would break text selection and desktop clicks.

## Review Focus

- A plain LMB press outside PiP must never be consumed — the dynamic bind must be unbound whenever the active window is not PiP.
- A second focus change to PiP must not double-bind; a second focus change away must not double-unbind.
- Short clicks on PiP must pass through (drag threshold), while drags move the window.
- The reload command must work with the live IPC instance on `wayland/wayland-1` despite `DISPLAY=:1` in the environment.
- The reload fallback must target the existing shell (`qs -n -p`), never a second independent instance.

---

### Task 1: Dynamic PiP-only LMB drag

**Files:**
- Modify: `defaults/hyprland/keybinds.json` (`preamble` array, immediately before `"customPreamble"` at line 208)
- Test: `tests/test_pip_lmb_bind.py` (create)

**Interfaces:**
- Consumes: `preamble` array in the catalog; generator `main()` renders it verbatim into main Lua.
- Produces: preamble Lua block with `hl.on("window.active", ...)` and the generated main Lua containing one active `hl.bind("mouse:272", ...)`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_pip_lmb_bind.py` following `tests/test_record_bind.py` style:

```python
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "defaults/hyprland/keybinds.json"


class PipLmbBindTest(unittest.TestCase):
    def test_preamble_contains_pip_lmb_block(self):
        preamble = "\n".join(json.loads(CATALOG.read_text())["preamble"])
        for needle in (
            'hl.config({ binds = { drag_threshold = 10 } })',
            'hl.on("window.active", function(w)',
            'w.class == "zen"',
            'w.title == "Picture-in-Picture"',
            'hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true })',
            'hl.unbind("mouse:272")',
        ):
            self.assertIn(needle, preamble, needle)

    def test_generator_emits_exactly_one_pip_lmb_bind(self):
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / "main.lua"
            custom = Path(tmp) / "custom.lua"
            subprocess.run([
                "python3", str(ROOT / "scripts/hyprland/generate_keybinds.py"),
                "--catalog", str(CATALOG),
                "--main-out", str(main), "--custom-out", str(custom),
            ], check=True, capture_output=True, text=True)
            lua = (main.read_text() + custom.read_text()).splitlines()
        binds = [line for line in lua if line.startswith('hl.bind("mouse:272"')]
        self.assertEqual(len(binds), 1, "expected one plain LMB bind")
        self.assertIn('hl.dsp.window.drag()', binds[0])
        self.assertIn('mouse = true', binds[0])
        super_binds = [line for line in lua if line.startswith('hl.bind("SUPER + mouse:272"')]
        self.assertEqual(len(super_binds), 1, "SUPER+LMB must remain bound")

    def test_pip_block_unbinds_only_after_binding(self):
        preamble = "\n".join(json.loads(CATALOG.read_text())["preamble"])
        bound = preamble.index('hl.bind("mouse:272"')
        unbound = preamble.index('hl.unbind("mouse:272")')
        self.assertLess(bound, unbound)
        self.assertEqual(preamble.count('hl.bind("mouse:272"'), 1)
        self.assertEqual(preamble.count('hl.unbind("mouse:272")'), 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest tests.test_pip_lmb_bind -v`
Expected: FAIL on `test_preamble_contains_pip_lmb_block` with `AssertionError: hl.config(...) not found`.

- [ ] **Step 3: Append the PiP LMB block to the catalog preamble**

Append these entries as the last elements of the `preamble` array, before `"customPreamble"`:

```json
  "",
  "-- >>> end4-pC PiP LMB grab (managed by end4-pC)",
  "hl.config({ binds = { drag_threshold = 10 } })",
  "local end4pcPipLmbBound = false",
  "hl.on(\"window.active\", function(w)",
  "    local end4pcIsPip = w ~= nil and w.class == \"zen\" and w.title == \"Picture-in-Picture\"",
  "    if end4pcIsPip and not end4pcPipLmbBound then",
  "        hl.bind(\"mouse:272\", hl.dsp.window.drag(), { mouse = true })",
  "        end4pcPipLmbBound = true",
  "    elseif not end4pcIsPip and end4pcPipLmbBound then",
  "        hl.unbind(\"mouse:272\")",
  "        end4pcPipLmbBound = false",
  "    end",
  "end)",
  "-- <<< end4-pC PiP LMB grab"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest tests.test_pip_lmb_bind -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Check generator, syntax and validator**

```bash
python3 scripts/hyprland/generate_keybinds.py --catalog defaults/hyprland/keybinds.json \
  --main-out /tmp/opencode/pip-main.lua --custom-out /tmp/opencode/pip-custom.lua \
  --commands-out /tmp/opencode/pip-commands.json
luac -p /tmp/opencode/pip-main.lua /tmp/opencode/pip-custom.lua
python3 scripts/hyprland/validate_keybind_catalog.py --catalog defaults/hyprland/keybinds.json
```
Expected: generator prints 213 binds / 51 bridges; `luac -p` silent; validator prints OK with 213 catalog / 211 hyprctl binds.

- [ ] **Step 6: Commit**

```bash
git add defaults/hyprland/keybinds.json tests/test_pip_lmb_bind.py
git commit -m "feat(keybinds): grab PiP window with plain LMB"
```

---

### Task 2: Fix CTRL+SUPER+R reload command

**Files:**
- Modify: `defaults/hyprland/keybinds.json` (`bind-26` raw `code` and `command` if present)
- Test: `tests/test_reload_bind_command.py` (create)

**Interfaces:**
- Consumes: `bind-26` raw bind from Task 1's catalog.
- Produces: raw command that invokes live IPC with `WAYLAND_DISPLAY=wayland-1` and falls back to `qs -n -p`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_reload_bind_command.py`:

```python
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "defaults/hyprland/keybinds.json"


class ReloadBindCommandTest(unittest.TestCase):
    def test_catalog_reload_bind_uses_live_ipc_and_no_duplicate_fallback(self):
        catalog = json.loads(CATALOG.read_text())
        bind = next(b for b in catalog["binds"] if b["id"] == "bind-26")
        self.assertEqual(bind["combo"], "CTRL + SUPER + R")
        self.assertIn('"env WAYLAND_DISPLAY=wayland-1 " .. qsIpcCall .. " wallpapers reloadShell', bind["code"])
        self.assertIn("qs -n -p $HOME/.config/quickshell/$qsConfig", bind["code"])
        self.assertNotIn("|| qs -p", bind["code"])

    def test_generated_lua_reload_bind_matches_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / "main.lua"
            custom = Path(tmp) / "custom.lua"
            subprocess.run([
                "python3", str(ROOT / "scripts/hyprland/generate_keybinds.py"),
                "--catalog", str(CATALOG),
                "--main-out", str(main), "--custom-out", str(custom),
            ], check=True, capture_output=True, text=True)
            lua = (main.read_text() + custom.read_text()).splitlines()
        reload_lines = [line for line in lua if line.startswith('hl.bind("CTRL + SUPER + R"')]
        self.assertEqual(len(reload_lines), 1)
        self.assertIn("WAYLAND_DISPLAY=wayland-1", reload_lines[0])
        self.assertIn("qs -n -p", reload_lines[0])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest tests.test_reload_bind_command -v`
Expected: FAIL on `test_catalog_reload_bind_uses_live_ipc_and_no_duplicate_fallback`.

- [ ] **Step 3: Replace the reload command**

In `bind-26`, replace the raw `code` string with:

```json
"code": "hl.bind(\"CTRL + SUPER + R\", function() hl.dispatch(hl.dsp.exec_cmd(\"env WAYLAND_DISPLAY=wayland-1 \" .. qsIpcCall .. \" wallpapers reloadShell || qs -n -p $HOME/.config/quickshell/$qsConfig\")) end, { description = \"Shell: Reload theme\" })"
```

Keep `dispatch.kind = "raw"`, `dispatch.code`, and the description unchanged; mirror the new string into both `dispatch.code` and the top-level `code`. There is no `command` field on this raw bind.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest tests.test_reload_bind_command -v`
Expected: PASS (2 tests).

- [ ] **Step 5: Regenerate live files and verify the bind live**

```bash
python3 scripts/hyprland/generate_keybinds.py --catalog defaults/hyprland/keybinds.json \
  --main-out /home/dmitriy/.config/hypr/hyprland/keybinds.lua \
  --custom-out /home/dmitriy/.config/hypr/custom/keybinds.lua \
  --commands-out /home/dmitriy/.config/quickshell/end4-pC/state/generated-commands.json
hyprctl binds -j | python3 -c 'import json,sys; print([b for b in json.load(sys.stdin) if b.get("key")=="R" and b.get("modmask")==68])'
```
Expected: generator prints 213 binds / 51 bridges; live bind is present but still shows the old command until the user reloads.

- [ ] **Step 6: Full verification and commit**

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/hyprland/validate_keybind_catalog.py --catalog defaults/hyprland/keybinds.json
python3 scripts/diagnostics/keybind-audit.py --skip-live
git add defaults/hyprland/keybinds.json tests/test_reload_bind_command.py
git commit -m "fix(keybinds): make CTRL+SUPER+R reach the live shell"
```
Expected: all tests pass, validator OK, audit 0 issues. Do not trigger the reload in this step; the user will reload.
