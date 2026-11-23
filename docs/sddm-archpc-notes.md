# archpc greeter user-list diagnosis (2026-11-23)

## Symptom

The ii-sddm-theme greeter on `archpc` showed no user tiles — the user selector was
a blank button and clicking it did nothing.

## Confirmed findings

- Only one SDDM stack is running: `sddm` (PID 1655 at diagnosis time), one Xorg on
  vt2, one `sddm-greeter-qt6` greeter. No orphan greeter/X stacks remain.
- SDDM package: `sddm 0.21.0-8`. Local working machine: `0.21.0-7`.
- Active config `/etc/sddm.conf.d/ii-sddm-theme.conf`:
  - `[General] DisplayServer=x11`, `InputMethod=qtvirtualkeyboard`
  - `[Users] MinimumUid=1000`, `MaximumUid=60513`
  - `[Theme] Current=ii-sddm-theme`
  - Greeter environment: `QML2_IMPORT_PATH=/usr/share/sddm/themes/ii-sddm-theme/Components/`,
    `QT_IM_MODULE=qtvirtualkeyboard`
  - No `HideUsers` or `HideShells` anywhere in `/etc/sddm.conf` or `/etc/sddm.conf.d/`.
    The `*.bak-20261123-121553` file is not a `.conf` file and is ignored by SDDM.
- Greeter process environment matches the drop-in: `DISPLAY=:0`, `HOME=/var/lib/sddm`,
  `XDG_RUNTIME_DIR=/run/user/955`, `XAUTHORITY=/tmp/xauth_ZxnTrL`.
- `dmitriy` exists (uid 1000, home `/home/dmitriy`, shell `/usr/bin/fish`). `fish` is
  listed in `/etc/shells`, and `sudo -u sddm getent passwd dmitriy` succeeds.
- The greeter's `UserButton.qml` matches the local copy except for the local avatar
  special case; both read `userModel` roles 257 (name) and 260 (icon).
- SDDM journal since the last restart shows only a clean startup: greeter started,
  `Message received from greeter: Connect`, no user/shell/uid filter errors.

## Root cause established for the original failure

A previous config used `MaximumUid=4294967294`. SDDM parses this field as a signed
32-bit int, so the value wrapped to 0 and excluded every user — `userModel.count`
was 0, which produces exactly the observed blank button. The active config now uses
`MaximumUid=60513`, which is in range and includes uid 1000. This fix was applied on
2026-11-23 before the currently running SDDM process started, so it is loaded.

## Deferred verification (could not be completed)

The device is reachable only over SSH and VNC is unavailable, so the live greeter
could not be observed or interacted with. A root-window screenshot of `:0` was
entirely black, so it could not confirm whether the tile list is now rendered.
The following checks remain open and must be done by someone at the console:

1. Unlock archpc, switch to vt2, and confirm whether `dmitriy` appears in the user list.
2. If the list is still empty, test the `MinimumUid` boundary by temporarily setting
   it to `999`, restarting SDDM, and re-checking; revert if it does not help.
3. If still empty, try aligning the greeter environment with the working local setup
   (`[X11] SessionDir=/usr/share/xsessions`, optionally `DisplayServer=x11-user`),
   restarting SDDM each time and reverting any change that does not fix the list.
4. Confirm Hyprland loads in normal mode (not the safe-mode dialog) after login.

No further config changes were made on archpc during this diagnosis: changing SDDM
settings or restarting the daemon would terminate the active session, which the user
deferred.
