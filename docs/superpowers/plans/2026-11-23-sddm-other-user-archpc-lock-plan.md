# SDDM User Auth, archpc Greeter, and Lock/Reload Bridge Implementation Plan

> **2026-11-24 — Task 2 superseded.** The user reversed the UI decision: the
> greeter keeps an always-visible dropdown with an appended **"Other user"**
> option, and choosing it reveals a username field above the password field.
> The theme is now the `rusnakdima/ii-sddm-theme` fork (commit `a476cea`),
> integrated as a git submodule at `sddm/ii-sddm-theme`. The old
> `UsernameField.qml` approach and its test have been removed/replaced. Tasks
> 1, 3, 4 and 5 remain valid except that "vendor" now means "submodule".

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SDDM authenticate arbitrary typed usernames, restore archpc's greeter user list, and eliminate the lock-during-reload crash by bridging with stock hyprlock while keeping the themed lock screen primary.

**Architecture:** Three linked deliverables in one repo: (1) vendor the locally-modified `ii-sddm-theme` into `end4-pC/sddm/ii-sddm-theme` and make `install.sh` update code without clobbering per-device generated config; (2) replace the `ii` greeter's collapsed user dropdown with an always-on typed username field backed by `userModel` suggestions; (3) add runtime markers so a lock or reload races are covered by hyprlock, which is dismissed only after the theme's `WlSessionLock` is secure again. Deployment and push are performed as `dmitriy`, then verified on archpc after the user unlocks it.

**Tech Stack:** QML/QtQuick 6, Quickshell 0.3.2 (`Quickshell.Io.FileView`, `Quickshell.Wayland.WlSessionLock`, `IpcHandler`), SDDM + `sddm.login(name, password, session)`, `userModel` roles 257 (name) / 260 (icon), hyprlock, bash/fish shell scripts, git over SSH.

**Spec:** `/root/.opencode/plan/2026-11-23-sddm-other-user-archpc-lock-design.md` (written during plan mode; move both docs to `docs/superpowers/{specs,plans}/` when execution starts).

## Global Constraints

- Work from `/mnt/Other/THEMES/end4-pC`; remote is `git@github.com:rusnakdima/end4-pC.git`.
- **Run as root, but commit and push as `dmitriy`**: use `sudo -u dmitriy git -C /mnt/Other/THEMES/end4-pC ...` for every commit and push. Never use the root git identity (`OpenCode Merge <opencode-merge@localhost>`).
- Never run `sddm --version` on archpc — it hangs and spawns orphan Xorg/greeter stacks. Use `pacman -Q sddm` instead.
- Never write to the live config or hot-reload a Quickshell session while it is locked, except via the explicit bridge procedure in Task 3. `sync.sh:116-142` already refuses writes while locked; keep that behavior.
- Preserve per-device generated theme state on both devices: `Components/Settings.qml` variants, `Themes/ii-sddm.conf`, `Backgrounds/*`, and the hardcoded dmitriy avatar.
- `DisplayServer`: local = `x11-user`, archpc = `x11`. Do not unify them unless Task 4 proves it affects the greeter.
- Default panel family is `ii` (`Settings.qml:491`); the `waffle` family is out of scope.
- Shells are fish locally and remotely; write test/run scripts in bash with an explicit shebang and invoke them as `bash script.sh`.

## Review Focus

These conditions are implied by the spec but not fully exercised by unit tests; each has a test or live verification step in the owning task:

1. **userModel is empty (archpc's exact symptom)** — the greeter must still authenticate a typed username. → Task 2, smoke test with an empty model.
2. **Uppercase/whitespace in typed usernames** — `AllowUppercaseLettersInUsernames=false` must still lowercase the typed value; leading/trailing spaces must not break login. → Task 2, static contract test.
3. **Preserving device-generated config during reinstall** — overwriting `Settings.qml`/`ii-sddm.conf`/backgrounds would silently revert each device's theme. → Task 1, `tests/test-sddm-vendor.sh`.
4. **Lock arrives while a reload is already in progress** (the reported trigger, distinct from reload-while-locked) — hyprlock must start from `lock()` too, not only from `requestShellReload()`. → Task 3, live procedure 3b.
5. **Hyprlock dismissed too early** — if the theme lock is not yet `secure`, dismissing hyprlock leaves the session unlocked or shows Hyprland's dead-lock screen. → Task 3, live procedure 3c and the marker-order assertion.

---

### Task 1: Vendor the SDDM theme and make installs update safely

**Files:**
- Create: `sddm/ii-sddm-theme/` (full tree copied from `/usr/share/sddm/themes/ii-sddm-theme`)
- Create: `sddm/ii-sddm-theme/PATCHES.md`
- Create: `tests/test-sddm-vendor.sh`
- Modify: `install.sh:717-745` (`install_sddm_theme()`)

**Interfaces:**
- Consumes: installed theme at `/usr/share/sddm/themes/ii-sddm-theme`; `SOURCE_DIR` and `$ELEVATE` already defined in `install.sh`.
- Produces: vendored theme root at `sddm/ii-sddm-theme` for Task 2's edits; `install_sddm_theme()` semantic "overwrite code, preserve generated state" relied on by Task 5's deploy.

- [ ] **Step 1: Copy the installed theme into the repo, excluding generated binaries**

```bash
mkdir -p sddm/ii-sddm-theme
rsync -a --exclude='Backgrounds/background.*' --exclude='Backgrounds/placeholder.png' \
  /usr/share/sddm/themes/ii-sddm-theme/ sddm/ii-sddm-theme/
```

Run: `git status --short | head -40`
Expected: vendored QML/scripts/conf files appear as untracked; no large background binaries.

- [ ] **Step 2: Write `sddm/ii-sddm-theme/PATCHES.md`**

List each divergence from `github.com/3d3f/ii-sddm-theme` found during research: `Components/UserButton.qml` dmitriy avatar, `Components/Colors.qml` palette, `Components/Settings.qml`, `Themes/ii-sddm.conf`, `iiMatugen/sddm-theme-apply.sh` `run_root`, `iiMatugen/Settings.qml`, `noMatugen/Settings.qml`, `setup.sh` `sudo -n`. One line per file plus a one-line reason. This is documentation only; no behavior.

- [ ] **Step 3: Write the failing preservation test `tests/test-sddm-vendor.sh`**

Bash test with `set -euo pipefail` and a temp dir that:
1. Asserts `sddm/ii-sddm-theme/Components/Input.qml`, `Components/InputLogin.qml`, `Themes/ii-sddm.conf` exist.
2. Asserts `install.sh` reads the vendored path (grep for `sddm/ii-sddm-theme`).
3. Asserts the install function preserves generated state: grep that calls to overwrite `Settings.qml`, `ii-sddm.conf` and `Backgrounds/` are guarded by a `preserve` check (e.g. `[ ! -f "$dest" ]` or a `PRESERVE_GENERATED=1` branch). Name the exact guard `PRESERVE_GENERATED`.
4. Asserts no `Backgrounds/background.*` file is tracked: `git ls-files sddm/ii-sddm-theme/Backgrounds/background.*` is empty.

Run: `bash tests/test-sddm-vendor.sh`
Expected: FAIL on assertion 3 before Step 4.

- [ ] **Step 4: Rewrite `install_sddm_theme()` in `install.sh`**

Signature: `install_sddm_theme() -> int` (unchanged name/call site).
Behavior:
- Source = `${SOURCE_DIR}/sddm/ii-sddm-theme`; `require_sudo` as before.
- If dest missing: copy full tree.
- If dest exists: copy only code files (`*.qml`, `qmldir`, `*.js`, `setup.sh`, `check.sh`, `uninstall.sh`, `change_avatar.sh`, `PATCHES.md`), preserving `Components/Settings.qml`, `iiMatugen/Settings.qml`, `noMatugen/Settings.qml`, `Matugen/Settings.qml`, `Themes/ii-sddm.conf`, and everything under `Backgrounds/`.
- Implement the skip with an explicit `PRESERVE_GENERATED=1` guard variable so Step 3's test can pin it.
- Keep the existing `Backgrounds` mkdir and wallpaper-copy behavior, and leave `install_wallpaper_sync()` untouched.

- [ ] **Step 5: Run the test and the shell syntax check**

Run: `bash tests/test-sddm-vendor.sh && bash -n install.sh`
Expected: both PASS.

- [ ] **Step 6: Commit as dmitriy**

```bash
sudo -u dmitriy git add sddm tests/test-sddm-vendor.sh install.sh
sudo -u dmitriy git commit -m "feat(sddm): vendor ii-sddm-theme and preserve generated config on install"
```

---

### Task 2: Always-on username field in the `ii` greeter

**Files:**
- Create: `sddm/ii-sddm-theme/Components/UsernameField.qml`
- Create: `tests/test-sddm-username-field.sh`
- Modify: `sddm/ii-sddm-theme/Components/Input.qml:22-69` (replace `UserButton { id: selectUser }`)
- Modify: `sddm/ii-sddm-theme/Components/InputLogin.qml:122-126, 273-284` (login calls + enable condition + reset)

**Interfaces:**
- Consumes: global `userModel` from SDDM; roles 257 (name), 260 (icon); `Appearance`/`Colors` from the theme; `config.AllowUppercaseLettersInUsernames`, `config.AllowEmptyPassword`, `inputContainer.selectedSession`.
- Produces: `UsernameField.qml` with API `id: selectUser` compatibility — `readonly property string currentText`, `property int currentIndex`, `signal selectionChanged()` — so `InputLogin.qml` keeps using `selectUser.currentText` unchanged. Suggestion popup lists `userModel` names and sets `currentText` on click.

- [ ] **Step 1: Write the failing contract test `tests/test-sddm-username-field.sh`**

Bash, `set -euo pipefail`. Assert:
1. `UsernameField.qml` exists and defines `currentText`, `currentIndex`, `selectionChanged`, and a `TextField`.
2. `UsernameField.qml` reads userModel role `257` and icon role `260`.
3. `Input.qml` instantiates `UsernameField` with `id: selectUser` and contains no `UserButton {` line.
4. Every `sddm.login(` in `InputLogin.qml` uses `selectUser.currentText` as the first argument (no hardcoded model-only derivation).
5. `InputLogin.qml` applies `.trim()` to the typed username in both login paths (Enter key and button click).
6. `AllowUppercaseLettersInUsernames == "false"` still lowercases `selectUser.currentText`.
7. The `TextField` is enabled independently of `userModel.count` — assert `UsernameField.qml` contains no `userModel.count` guard on the field's `enabled`/`visible` (an empty model must not disable typed-username login).

Run: `bash tests/test-sddm-username-field.sh`
Expected: FAIL at assertion 1 before Step 2.

- [ ] **Step 2: Create `UsernameField.qml`**

Implement a `FocusScope` containing a `TextField` and a suggestion `Popup`/`ListView`:
- `property alias currentText: usernameField.text`, `property int currentIndex: -1`, `signal selectionChanged()`.
- `model: userModel`; delegate text = `userModel.data(userModel.index(index,0), 257)`; avatar source = role 260, with the existing dmitriy avatar special case preserved from `UserButton.qml:116`.
- Popup opens on text edit/`down` key, closes on selection/Escape; selecting a row sets `currentText` to that row's name.
- Keyboard Enter in the field must be forwarded so `InputLogin.qml`'s `onAccepted` path can still log in (do not swallow the key).
- Style with existing `Appearance`/`Colors` properties; no new dependencies.

- [ ] **Step 3: Swap the component in `Input.qml`**

Replace `UserButton { id: selectUser }` with `UsernameField { id: selectUser }` inside `usernameFieldContainer/innerRow`, keeping `LayoutButton` and the `property alias selectUser: selectUser` on the container. No other changes to `Input.qml`.

- [ ] **Step 4: Adjust login validation in `InputLogin.qml`**

At lines 122-126 and 273-284: compute `const typedUser = selectUser.currentText.trim()`; use `config.AllowUppercaseLettersInUsernames == "false" ? typedUser.toLowerCase() : typedUser` as the first `sddm.login(...)` argument. At line 273 include `typedUser !== ""` in the login-button enable condition. At line 487 clear the typed username too on `loginFailed`. Leave `sddm.login(user, password.text, inputContainer.selectedSession)` argument order unchanged.

- [ ] **Step 5: Run static checks**

Run: `bash tests/test-sddm-username-field.sh`
Expected: PASS.

Run: `/usr/lib/qt6/bin/qmllint sddm/ii-sddm-theme/Components/UsernameField.qml 2>&1 | grep -v 'SddmComponents' || true`
Expected: no syntax errors attributable to the new file (unresolved SddmComponents/theme imports are acceptable in this standalone check).

- [ ] **Step 6: Live greeter smoke test (local device, unlocked only)**

Run: `sudo sddm-greeter --test-mode --theme /usr/share/sddm/themes/ii-sddm-theme` after temporarily installing the edited theme to a scratch path (e.g. `/usr/share/sddm/themes/ii-sddm-test/`), then confirm visually: username field visible; typing a name and a password reaches `sddm.login`; suggestions appear from `userModel`; no QML errors in stderr. Remove the scratch theme afterwards.

Expected: no crash, field and suggestions render, login attempt is dispatched with the typed name (a wrong password should produce the normal "Incorrect password" shake). Repeat once with `MinimumUid` temporarily set to a value that hides all users (or with `userModel` empty in test mode): the username field must remain editable and a typed-name login attempt must still be dispatched. Restore the config immediately.

- [ ] **Step 7: Commit as dmitriy**

```bash
sudo -u dmitriy git add sddm/ii-sddm-theme tests/test-sddm-username-field.sh
sudo -u dmitriy git commit -m "feat(sddm): allow typing an arbitrary username in the ii greeter"
```

---

### Task 3: hyprlock bridge for lock/reload races

**Files:**
- Modify: `GlobalStates.qml:56-113` (markers + bridge functions + `requestShellReload()` + `lock()`)
- Modify: `modules/common/panels/lock/LockScreen.qml:89-100` (`onSecureChanged`)
- Create: `tests/test-lock-bridge.sh`
- Deploy-copy: `/home/dmitriy/.config/hypr/hyprlock.conf` on local (source available at archpc)

**Interfaces:**
- Consumes: existing `lockStatePath`/`lockStateFile` and `screenLocked` in `GlobalStates.qml`; `lock.secure` in `LockScreen.qml`; `Config.options.lock.useHyprlock`.
- Produces: `GlobalStates` API `readonly property string reloadMarkerPath`, `readonly property string bridgeMarkerPath`, `function startHyprlockBridge(): void`, `function endHyprlockBridge(): void`; `LockScreen` calls `GlobalStates.endHyprlockBridge()` when secure. `IpcHandler lock status` must keep reporting theme lock state.

- [ ] **Step 1: Write the failing contract test `tests/test-lock-bridge.sh`**

Bash, `set -euo pipefail`. Assert:
1. `GlobalStates.qml` defines both marker paths ending in `end4-pC-reloading` and `end4-pC-hyprlock-bridge`.
2. `requestShellReload()` calls `startHyprlockBridge()` before `Quickshell.reload(true)` when `screenLocked` is true.
3. `lock()` calls `startHyprlockBridge()` when the reload marker is present (covers "locking during a reload").
4. `endHyprlockBridge()` checks the theme lock is secure before terminating hyprlock — assert the function body contains `lock.secure` or is only called from `onSecureChanged` guarded by `lock.secure`.
5. `LockScreen.qml`'s `onSecureChanged` calls `GlobalStates.endHyprlockBridge()`.
6. `Config.qml` default `useHyprlock` remains `false` (theme lock primary), and `GlobalStates.lock()` retains the `useHyprlock` opt-in branch.

Run: `bash tests/test-lock-bridge.sh`
Expected: FAIL at assertion 1 before Step 2.

- [ ] **Step 2: Add markers and bridge functions in `GlobalStates.qml`**

Using the same `FileView` pattern as `lockStateFile` (`blockLoading: true, blockWrites: true, atomicWrites: true, watchChanges: false`), add two paths under `XDG_RUNTIME_DIR`: `${...}/end4-pC-reloading` and `${...}/end4-pC-hyprlock-bridge`, with `FileView`s named `reloadMarkerFile` and `bridgeMarkerFile`.

`startHyprlockBridge()`: if bridge marker already set, return; write it; start hyprlock with the existing detached pattern `Quickshell.execDetached(["bash","-c","pidof hyprlock || hyprlock"])` (reuse the call from `lock()`).

`endHyprlockBridge()`: only clear the bridge marker and `pkill -TERM hyprlock` when called from the secure path; never leave hyprlock running when the theme lock is secure, and never kill it when the theme lock is not secure.

- [ ] **Step 3: Modify `requestShellReload()` and `lock()`**

`requestShellReload()`: when `root.screenLocked && !Config.options.lock.useHyprlock`, call `startHyprlockBridge()` and write the reload marker **before** `Quickshell.reload(true)`; otherwise just reload. Do not defer or skip the reload (verification reloads while locked must still happen).

`lock()`: keep the `useHyprlock` branch. In the theme-lock branch, before writing the lock state, if the reload marker file is non-empty call `startHyprlockBridge()`. Then keep `writeLockState(true)` followed by `screenLocked = true` in that order.

On startup, `initLockState()` must clear the reload marker after restoring `screenLocked` from the existing lock marker, so a stale marker cannot start a bridge on the next lock.

- [ ] **Step 4: Hand back to the theme lock in `LockScreen.qml`**

In `WlSessionLock.onSecureChanged`, after the existing `startupLockPending` handling, call `GlobalStates.endHyprlockBridge()` only when `lock.secure && GlobalStates.screenLocked && !Config.options.lock.useHyprlock`. Keep `locked: GlobalStates.screenLocked && !Config.options.lock.useHyprlock` unchanged.

- [ ] **Step 5: Provide local hyprlock config**

Local has only `~/.config/hypr/hyprlock/colors.conf`. Copy the working archpc config and supporting scripts as dmitriy:

```bash
scp root@archpc:/home/dmitriy/.config/hypr/hyprlock.conf /tmp/opencode/hyprlock.conf
install -o dmitriy -g dmitriy -m 644 /tmp/opencode/hyprlock.conf /home/dmitriy/.config/hypr/hyprlock.conf
```

Verify referenced `check-capslock.sh` / `status.sh` exist locally; if missing, copy them from archpc too or remove those label blocks. Verify with `hyprlock --help >/dev/null 2>&1` (config parse check) — do not start a lock during this step.

- [ ] **Step 6: Run static checks**

Run: `bash tests/test-lock-bridge.sh && ./tests/qml-compile-check.sh`
Expected: both PASS; no new QML compile errors in `GlobalStates.qml` or `LockScreen.qml`.

- [ ] **Step 7: Live regression procedures (local device, unlocked)**

3a. Lock normally → confirm the themed lock screen appears, `qs -c end4-pC ipc call lock status` prints `locked`, no hyprlock process.
3b. **Lock during a reload** (the reported trigger): start a reload (`Quickshell.reload` / the theme's reload action), then immediately lock. Expected: no "oopsie daisy" panel, no Hyprland dead-lock screen, hyprlock process present during the reload.
3c. Wait for the reloaded theme to re-acquire the lock. Expected: `lock.secure` true → hyprlock process gone, themed lock screen visible, `ipc call lock status` still `locked`.
3d. Unlock normally. Expected: keyring unlock / fingerprint / `alsoInhibitIdle` behavior unchanged because the theme lock remained primary.

- [ ] **Step 8: Commit as dmitriy**

```bash
sudo -u dmitriy git add GlobalStates.qml modules/common/panels/lock/LockScreen.qml tests/test-lock-bridge.sh
sudo -u dmitriy git commit -m "fix(lock): bridge reloads with hyprlock while keeping the themed lock"
```

---

### Task 4: Diagnose and fix archpc's empty greeter user list

**Files:**
- Modify: `/etc/sddm.conf.d/ii-sddm-theme.conf` on archpc (minimal diff only)
- Modify: `~/OMP_ROOT/openspec/changes/archpc-sddm-fix/tasks.md` on archpc (check off completed verification tasks)

**Interfaces:**
- Consumes: the diagnostics below and the Task 2 username field deployed in Task 5.
- Produces: a documented root cause and the minimal config change that makes `userModel` non-empty on archpc.

- [ ] **Step 1: Confirm device state after unlock**

Ask the user to unlock archpc. Confirm whether Hyprland came up in **normal** mode or the safe-mode dialog observed by the reviewer. If safe mode, fix that first (`Hyprland` config validation, e.g. `hyprctl --check`) — a lock bridge depends on a normally loaded compositor config.

- [ ] **Step 2: Confirm only one SDDM stack is running**

Run: `ssh -o BatchMode=yes root@archpc "ps -eo pid,ppid,cmd | grep -E 'sddm|Xorg' | grep -v grep"`
Expected: exactly one `/usr/bin/sddm`, one Xorg on vt2, one greeter. If extra stacks exist, kill only the orphans (never PID 1655's tree from the research snapshot).

- [ ] **Step 3: Capture the real greeter's config view**

Run (replace `<greeter-pid>` with the live greeter PID):

```bash
ssh -o BatchMode=yes root@archpc "tr '\\0' '\\n' < /proc/<greeter-pid>/environ | grep -E 'QML2_IMPORT_PATH|QT_IM_MODULE|DISPLAY|HOME'; grep -rIn -E 'MinimumUid|MaximumUid|HideUsers|HideShells' /etc/sddm.conf /etc/sddm.conf.d/"
```

Expected: the greeter sees the drop-in; no `HideUsers`/`HideShells`; `MinimumUid=1000`, `MaximumUid=60513`.

- [ ] **Step 4: Test the MinimumUid boundary**

Run: `ssh -o BatchMode=yes root@archpc "systemctl restart sddm"` after temporarily setting `MinimumUid=999` in the drop-in, then have the user check the greeter on vt2 (do **not** use `sddm --version`). If users appear, the boundary was the cause; keep `999` and document why. If not, revert to `1000` and continue to Step 5.

- [ ] **Step 5: Align greeter environment with the working local config if needed**

If Step 4 does not fix it, make the minimal change: add `[X11] SessionDir=/usr/share/xsessions` to archpc's drop-in and/or temporarily set `DisplayServer=x11-user` as on local, restart SDDM, and re-check. Revert any change that does not fix the list. Record the exact effective diff.

- [ ] **Step 6: Verify acceptance and document**

Acceptance: the vt2 greeter shows `dmitriy` in the user list, selecting it and entering the password logs in, and the Task 2 username field also accepts a typed name. Update `archpc-sddm-fix/tasks.md` by checking off the previously open verification tasks (3.5/3.6/7.4/7.5/8.x) that are now proven, and write the root cause into the change's proposal/design notes.

- [ ] **Step 7: Commit the repo-side documentation (if any) as dmitriy**

If the diagnosis produced a repo-side note (e.g. `docs/sddm-archpc-notes.md`), commit it as dmitriy with message `docs(sddm): record archpc greeter user-list root cause`.

---

### Task 5: Push, deploy, and final verification

**Files:**
- Modify: push/deploy commands only
- Move: the design and plan docs into `docs/superpowers/specs/` and `docs/superpowers/plans/` at execution time

**Interfaces:**
- Consumes: commits from Tasks 1-4.
- Produces: pushed `main` on `git@github.com:rusnakdima/end4-pC.git`; deployed theme on both devices; verified greeter and lock behavior.

- [ ] **Step 1: Move the planning docs and commit them**

```bash
mkdir -p docs/superpowers/specs docs/superpowers/plans
cp /root/.opencode/plan/2026-11-23-sddm-other-user-archpc-lock-design.md docs/superpowers/specs/
cp /root/.opencode/plan/2026-11-23-sddm-other-user-archpc-lock-plan.md docs/superpowers/plans/
sudo -u dmitriy git add docs/superpowers
sudo -u dmitriy git commit -m "docs: add SDDM auth and lock bridge design and plan"
```

- [ ] **Step 2: Run all static tests before pushing**

Run: `bash tests/test-sddm-vendor.sh && bash tests/test-sddm-username-field.sh && bash tests/test-lock-bridge.sh && ./tests/run-qml-tests.sh`
Expected: all PASS.

- [ ] **Step 3: Push as dmitriy**

```bash
sudo -u dmitriy git -C /mnt/Other/THEMES/end4-pC push origin HEAD
```

Verify: `sudo -u dmitriy git -C /mnt/Other/THEMES/end4-pC log -1 --format='%an <%ae> %h %s'`
Expected: author/committer is `dmitriy`, and the remote ref matches HEAD.

- [ ] **Step 4: Deploy the vendored theme to both devices**

For local: re-run `install.sh` (or the `install_sddm_theme()` path) so code files update while generated config/backgrounds are preserved. For archpc:

```bash
rsync -av --exclude='Backgrounds/' --exclude='*/Settings.qml' --exclude='Themes/ii-sddm.conf' \
  /mnt/Other/THEMES/end4-pC/sddm/ii-sddm-theme/ root@archpc:/usr/share/sddm/themes/ii-sddm-theme/
```

Then `ssh root@archpc "chown -R dmitriy:dmitriy /usr/share/sddm/themes/ii-sddm-theme"`.

- [ ] **Step 5: Final verification on archpc after user unlock**

Confirm: greeter user list shows `dmitriy`; typed-username login works; SDDM has no crash loop (`journalctl -u sddm --since '-1 hour'`); Quickshell version/config matches local; lock-during-reload produces no crash panel (repeat Task 3 step 3b if the user agrees).

- [ ] **Step 6: Report results**

Post/summarize: pushed commit hash, root cause found on archpc, config diff applied, and verification outcomes (including anything still blocked on the user unlocking the device).
