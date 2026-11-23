# Design: SDDM user auth, archpc greeter, and lock/reload crash

Date: 2026-11-23
Repo: `/mnt/Other/THEMES/end4-pC` (HEAD `14013cc`, clean, remote `git@github.com:rusnakdima/end4-pC.git`)

## Intent and why

Three linked problems reported by the user:

1. The SDDM greeter only lets you pick an existing user from a collapsed dropdown and type a password. The user wants correct authentication for arbitrary users: an always-on username field they can type into (chosen over an "Other user" dropdown row).
2. On the remote `archpc` device the SDDM user list is blank — the selector button is empty and clicking shows nothing, i.e. `userModel.count === 0`.
3. Locking the local session **during** a Quickshell theme reload produces the Quickshell crash panel ("oopsie daisy"). This is distinct from the older "reload while locked" bug that commit `6688a9c` addressed.

Also required: make and push the changes as user `dmitriy` (we are root), then deploy to `archpc` and verify after the user unlocks that device.

## Findings that constrain the design

- **The SDDM greeter is not tracked in `end4-pC` today.** It is `ii-sddm-theme` (upstream `github.com/3d3f/ii-sddm-theme`), installed at `/usr/share/sddm/themes/ii-sddm-theme`. `install.sh:717-745` only copies it from a sibling `ii-sddm-theme/` dir that no longer exists, so the installed copy is the source of truth.
- **Local modifications vs upstream must be preserved**: `Components/UserButton.qml` (hardcoded `dmitriy` avatar), `Components/Colors.qml` (custom palette), `Components/Settings.qml`, `Themes/ii-sddm.conf` (video background + placeholder), `iiMatugen/sddm-theme-apply.sh` (root-aware `run_root`), `iiMatugen/Settings.qml`, `noMatugen/Settings.qml`, `setup.sh` (`sudo -n`). `install.sh` also owns the wallpaper-sync script, sudoers rule, and `switchwall.sh` hook.
- **Greeter user flow**: `Input.qml` hosts `UserButton { id: selectUser }` plus `LayoutButton`; `InputLogin.qml` builds the username from `selectUser.currentText` (lowercased unless `AllowUppercaseLettersInUsernames`) and calls `sddm.login(user, password.text, inputContainer.selectedSession)`. `UserButton.qml` is a collapsed `ListView { model: userModel }` with name role `257`, icon role `260`, `currentIndex: userModel.lastIndex`. Because `selectUser` is an id in `Input.qml`'s context, a replacement component can keep that id/API and leave `InputLogin.qml` almost untouched.
- **archpc facts (read-only probes)**: reachable via `ssh -o BatchMode=yes root@archpc`; SDDM active on X11 since `2026-11-23 23:16:07 +05`, **after** the config fix at `12:16:07` (`MaximumUid=60513` replaced the overflowing `4294967294`). Only `dmitriy` (uid 1000, `/usr/bin/fish` in `/etc/shells`, password set) qualifies; `sudo -u sddm getent passwd dmitriy` works; SDDM journal shows no user errors. Local working config uses `DisplayServer=x11-user` and `[X11] SessionDir=/usr/local/share/xsessions`; archpc uses `DisplayServer=x11` and no `[X11]` section. `Main.qml` is identical; `Settings.qml` differs in generated values.
- **Two orphan greeter/Xorg stacks on vt1/vt4 were created by my own `sddm --version` probes and have been killed.** Only the legitimate SDDM/greeter on vt2 remains. The reviewer also observed a Hyprland safe-mode dialog on archpc; the user must confirm whether unlocking lands in normal or safe mode.
- **Lock flow**: `GlobalStates.qml` `requestShellReload()` calls `Quickshell.reload(true)`; `lock()` writes `${XDG_RUNTIME_DIR}/end4-pC-locked` and sets `screenLocked = true`. `LockScreen.qml` owns a `WlSessionLock` with `locked: GlobalStates.screenLocked && !Config.options.lock.useHyprlock`. The marker fixes reload-while-locked, but not a lock request arriving while the engine is torn down.
- **hyprlock availability**: installed on both devices (`/usr/bin/hyprlock`). archpc has a full `~/.config/hypr/hyprlock.conf` plus `hyprlock/colors.conf`; local has only `hyprlock/colors.conf` — a `hyprlock.conf` must be provided on local.

## Goals

1. Vendor the locally-modified `ii-sddm-theme` into `end4-pC` as a tracked directory and make `install.sh` install/update from there without clobbering per-device generated config.
2. Replace the SDDM user dropdown with an always-on free-form username field, backed by `userModel` as suggestions, passing the typed username to `sddm.login(...)`.
3. Diagnose and fix archpc's empty `userModel`, then verify the user list and login on that device after unlock.
4. Eliminate the lock-during-reload crash by using **stock hyprlock as a temporary bridge during reload**, while keeping the themed lock screen as the normal, primary lock.
5. Commit and push as `dmitriy`; deploy and verify on archpc.

## Non-goals / anti-goals

- No changes to PAM stacks, SDDM upstream source, or accountsservice.
- No permanent removal or redesign of the themed lock screen — it stays the primary lock UI.
- Do not clobber per-device generated theme config/backgrounds during deployment.
- Do not touch `pixl`, PAM, or session lists except where archpc greeter config needs alignment.

## Constraints

- Plan mode: no implementation until design approval and a written plan.
- Root shell: commit/push as `dmitriy` (`sudo -u dmitriy git -C /mnt/Other/THEMES/end4-pC ...`); SSH to archpc as root with BatchMode.
- Local and remote shells are fish — quote carefully; never run `sddm --version` on archpc again (it hangs and spawns orphan greeters).
- archpc is locked; the user unlocks it for verification.

## Approaches considered and chosen

### 1. Theme source location
- **Vendor into `end4-pC/sddm/ii-sddm-theme` (chosen)** — one repo, one push, easy management; not a submodule.
- Separate fork repo / patch-in-place: rejected (two pushes / fragile).

### 2. SDDM "Other user" UI
- **Always-on username field with suggestions (chosen)** — a visible `TextField` bound to `selectUser.currentText`, with `userModel` feeding a suggestion popup. Works even with an empty list (helps archpc). Implement as a new `UsernameField.qml` used in `Input.qml` under the existing `selectUser` id so `InputLogin.qml` needs only minor validation changes. Keep the dmitriy-avatar behavior.
- Dropdown "Other user" row / separate toggle: rejected by user.

### 3. archpc empty user list
- **Diagnose then fix at config/deployment level (chosen)** — re-check the real vt2 greeter after orphan cleanup; capture greeter environment/config precedence; test the `MinimumUid` boundary; align `DisplayServer`/`[X11] SessionDir` with the working local config if it affects the greeter. The new username field is a functional fallback, but the list must still work.

### 4. Lock-during-reload crash
- **hyprlock as reload bridge, themed lock primary (chosen by user after clarification)** — on a reload requested while locked, start stock hyprlock first so a stable, independent lock client covers the teardown window; the reloaded theme restores `screenLocked` from the marker and re-acquires `WlSessionLock`; only once the theme lock reports `secure` is hyprlock dismissed. All `screenLocked`-gated UI, IPC `lock status`, keyring/fingerprint unlock and `alsoInhibitIdle` behavior therefore survive unchanged. Force hyprlock's availability/config on both devices (not permanent activation).
- Permanent hyprlock / theme-lock-only hardening: rejected by user.

## The decided how

1. **Vendor theme**: create `end4-pC/sddm/ii-sddm-theme/` from the installed copy; add `PATCHES.md` listing divergences from upstream. Update `install.sh:install_sddm_theme()` to **overwrite code/QML files from the vendored dir but preserve** per-device generated files: `Settings.qml` variants, `Themes/ii-sddm.conf`, `Backgrounds/*`, and any local avatar. Track only source/text assets; regenerate binaries (builder decides exact set).
2. **Username field**: add `Components/UsernameField.qml` in the `ii` family — `TextField` for the typed name, popup of `userModel` suggestions (roles 257/260), avatar by name, `currentText` API. Swap it in for `UserButton` in `Input.qml` keeping `id: selectUser`. Update `InputLogin.qml` validation to trim the typed username and keep the uppercase/empty rules. Implement in `ii`; leave `waffle` unchanged (default family is `ii`).
3. **archpc**: after unlock, confirm normal vs safe-mode Hyprland; inspect the real vt2 greeter; test `MinimumUid=999` vs `1000`, config precedence, and `[X11] SessionDir`/`DisplayServer` alignment; apply the minimal fix and document it in the `archpc-sddm-fix` openspec change.
4. **Lock bridge**: in `GlobalStates.requestShellReload()`, if `screenLocked` is true, start hyprlock (via the same execDetached pattern as `lock()`) before `Quickshell.reload(true)` and record a "bridge" marker. On the reloaded instance, `initLockState()` restores the lock from the existing marker; in `LockScreen.qml`, when `lock.secure` becomes true and the bridge marker exists, terminate hyprlock and clear the marker. Never dismiss hyprlock unless the theme lock is secure, so there is never an unlocked gap; if re-lock fails, hyprlock stays.
5. **Delivery**: commit conventionally, push as `dmitriy`, deploy theme/config to archpc, restart SDDM/Quickshell as needed, verify after unlock (real greeter via logout/VT switch; `--test-mode` only as a sanity check, not acceptance).

## What is left to the builder

- Exact QML edits, new `UsernameField.qml`, and validation (`qmllint`, greeter smoke test).
- Exact list of vendored binary assets vs regenerated ones.
- Bridge marker lifecycle details and hyprlock process termination safety.
- Concrete archpc diagnostic commands and the resulting minimal config diff.
- Regression test: lock during reload → no crash panel, theme lock restored, hyprlock gone.
- Final commit message and push-as-`dmitriy` command sequence.
