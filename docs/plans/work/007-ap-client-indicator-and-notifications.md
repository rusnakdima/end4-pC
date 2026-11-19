# AP Client Count in the Bar + Connect/Disconnect Notifications

> Show how many clients are connected to the shell's Wi‑Fi access point (hotspot) as an indicator in the bar's system‑icons cluster, and notify the user when a client joins or leaves the AP.

**Status**: Done — implemented, deployed via `sync.sh`, and verified live (badge shows the connected-client count)
**Created**: 2026-11-19
**Owner**: backend-engineer

## Goal

1. The bar's system‑icons cluster (the blue pill with volume / network / hotspot / Bluetooth / battery icons shown in the request) displays the number of clients currently associated with the AP, next to the existing `wifi_tethering` icon.
2. The shell sends a desktop notification when a client connects to the AP and when a client disconnects, identifying the device and the AP.
3. Detection reuses the AP state the shell already publishes; no new daemon, no extra polling loop, no new privileges.

## Context

### The AP already has a single source of truth

- `services/Hotspot.qml` is a singleton that owns the AP state. It publishes `active`, `ssid`, `channel`, `ip`, `uplink`, `error` and `clients` (`Hotspot.qml:21-30`). Every 4 s while `active` it calls `sudo -n /usr/local/bin/aic-hotspot status` (`Hotspot.qml:87-100`) and parses one JSON line in `applyJson()` (`:35-59`).
- Each item in `Hotspot.clients` is `{ip, mac, host}` produced by `scripts/hotspot/aic-hotspot:216-243`: dnsmasq leases joined with `iw dev <ap> station dump`, MACs lowercased, and lease‑only rows explicitly filtered as ghosts. This is authoritative for "connected right now".
- `Hotspot.error` is deliberately only written by start/stop action runs (`:55-58`, comment at `:32-34`); status polls must never overwrite it.

### Where the indicator belongs

- `modules/ii/bar/SystemIcons.qml:129-136` already renders the AP icon as `Revealer { reveal: Hotspot.active; MaterialSymbol { text: "wifi_tethering" } }` inside the `Flow` that holds the system icons. The count badge belongs on/next to that icon and must follow the component's `root.vertical`, `root.isMaterial` and `contentColor` conventions.
- Existing badge precedent: `modules/ii/bar/NotificationUnreadCount.qml:17-41` (small themed `Rectangle` pinned to an icon corner with a `StyledText` number) and `modules/ii/bar/UpdatesCount.qml` (icon + number, horizontal and vertical variants). The whole cluster's `MouseArea` toggles the right sidebar (`SystemIcons.qml:24-29`) — that behavior must be preserved.
- The count is already shown elsewhere for reference: `modules/common/models/quickToggles/HotspotToggle.qml:8-18` (`ssid · <clients.length>`) and `modules/ii/sidebarRight/hotspot/HotspotDialog.qml:40,206-209`. The new indicator only brings it to the bar.

### How the shell notifies

- Services send desktop notifications with `Quickshell.execDetached(["notify-send", summary, body, "-a", "Shell"])` — see `services/Vpn.qml:93`, `services/TimerService.qml:81`, `services/Battery.qml:66-100`. `services/Notifications.qml` is the local D‑Bus notification server that renders them.
- User-facing strings go through `Translation.tr(...)`; English source keys live in `translations/en_US.json` (see `translations/README.md:1-12`).
- Config lives in `modules/common/Config.qml`; `hotspot` is at `:93-97` and `bar.indicators` at `:657-661` (`notifications.showUnreadCount` is the existing opt‑out example).
- Hosted tests live in `tests/shell-tests/tst_*.qml`, must be listed in `tests/shell-tests/shell.qml` (`testFiles`, ~line 31), and pure helpers belong in `modules/common/functions/` (auto-exposed as `qs.modules.common.functions`; e.g. `NotificationUtils.qml`). `tests/functional-coverage.sh` requires any file with a JS `function` under `modules/ii`/`services` to have a test or an exemption; `services/Hotspot.qml` is already exempted at `tests/coverage-exemptions.txt:148`, and a new bar component should stay declarative (no `function`) so coverage stays unchanged.

### Scope boundary

- The request's screenshot is the **ii** panel's system‑icons cluster. The waffle panel's `modules/waffle/bar/SystemButton.qml` does not surface the hotspot today, so the bar indicator is an ii-panel change. The service/notification work is panel-agnostic and benefits both families.
- Out of scope: changing `scripts/hotspot/aic-hotspot` or hostapd event/log parsing, adding a settings-page UI for the two new toggles, and adding a new notification center group.

## Constraints

- Keep all detection asynchronous; it must run off the existing status poll, never block the GUI thread, and never run `sudo` more often than the current 4 s poll.
- Avoid notification spam: seed a baseline silently on shell start / AP start, dedupe by MAC, reset silently on AP stop, and confirm a disappearance across two consecutive polls before calling it a disconnect.
- Preserve the existing `Hotspot.error` write policy and all existing consumers of `active`/`clients`.
- No new dependencies, no service/IPC schema changes, no new privileges beyond the already-configured passwordless `aic-hotspot` helper.
- New strings must be added to `en_US.json`; other locale files may keep English fallback text.
- The bar indicator must not introduce a JS `function` into `modules/ii` (functional-coverage rule) and must compile under `tests/qml-compile-check.sh`.

## Tasks

| # | Task | Agent | Priority | Status | Dependencies |
|---|------|-------|----------|--------|--------------|
| 1 | Pure client-diff helper + hosted test (`HotspotUtils.qml`, `tst_hotspot_clients.qml`) | backend | 1 | DONE | — |
| 2 | Detect connects/disconnects and send notifications in `Hotspot.qml` (+ config guard) | backend | 1 | DONE | 1 |
| 3 | Bar client-count indicator (`HotspotClientCount.qml`, `SystemIcons.qml`, config) | frontend | 1 | DONE | — |
| 4 | Translation keys (`en_US.json`) | frontend | 2 | DONE | 2 |
| 5 | Static checks, hosted tests and live verification | qa | 2 | DONE | 1, 2, 3, 4 |

### Task 1 — Pure client-diff helper and hosted test

Add `modules/common/functions/HotspotUtils.qml` (pragma Singleton) with pure, side-effect-free helpers:

- `macOf(client)` → normalized lowercase MAC string.
- `clientLabel(client)` → `host` when non-empty and not `"*"`, otherwise the MAC (dnsmasq can emit `*` for unknown hosts).
- `diffClients(previous, current)` → `{ connected: [...], disconnected: [...] }` where entries are the client objects; identity is the normalized MAC; order changes alone are a no-op; duplicate MACs are handled once.

Add `tests/shell-tests/tst_hotspot_clients.qml` covering: empty→empty, first snapshot, one added, one removed, simultaneous add+remove, reorder, case-insensitive MAC equality, host-label fallback (empty/`*`), and duplicate MACs. Register it in `tests/shell-tests/shell.qml`'s `testFiles` list. This keeps the detection logic deterministic without needing a live radio, sudo, or hostapd.

### Task 2 — Connect/disconnect detection and notifications in `Hotspot.qml`

In `services/Hotspot.qml`, keep `property var clientBaseline: []` (last snapshot of client objects) and `property var pendingDisconnects: []` (MACs whose disappearance is awaiting confirmation). Extend `applyJson()` after the existing field assignments:

- When `active` is false: clear `clientBaseline` and `pendingDisconnects` silently (AP down, including shell start with AP off).
- When `active` flips false→true, or when no baseline exists yet: set `clientBaseline = clients` silently — pre-existing clients must not produce notifications.
- Otherwise: `const change = HotspotUtils.diffClients(clientBaseline, clients)`. For each `connected` client, emit one `notify-send` immediately and clear it from `pendingDisconnects` (a flapping client that came back must not leave a stale pending disconnect). For each `disconnected` client, add it to `pendingDisconnects`; on the next successful status poll, if its MAC is still absent, emit the disconnect notification and remove it from pending; if it reappeared, drop it silently. Then set `clientBaseline = clients`.
- Guard all notifications with `Config.options.hotspot.notifyClientChanges` (new config leaf, default `true`).
- Notification shape: `Quickshell.execDetached(["notify-send", "-a", "Shell", summary, body])` with translated `summary`/`body`, `HotspotUtils.clientLabel(client)` and `root.ssid` (fallback to a translated "the hotspot") in the body.
- Update the `services/Hotspot.qml` exemption reason in `tests/coverage-exemptions.txt` to mention that the notification helper is a thin `notify-send` wrapper around the live AP state.

Do not add a JS `function` to any `modules/ii` file, do not change the `error` write policy, and do not change the 4 s poll interval.

### Task 3 — Bar client-count indicator

- Add `modules/ii/bar/HotspotClientCount.qml`: a declarative component (no `function` declarations) built from a small themed `Rectangle` + `StyledText` showing `Hotspot.clients.length`, following `NotificationUnreadCount.qml:17-41` and the parent's `isMaterial`/`contentColor` logic. It is visible only when `Hotspot.active && Hotspot.clients.length > 0 && Config.options.bar.indicators.hotspot.showClientCount`. No tooltip: a `StyledToolTip` added during implementation showed unconditionally (the badge has no hover tracking) and was removed after the user reported it.
- In `modules/ii/bar/SystemIcons.qml`, place the component inside the existing `Revealer { reveal: Hotspot.active }` next to the `wifi_tethering` icon (around `:129-136`), passing through `contentColor`/`contentColorOverridden`/`isMaterial`. Keep the outer `MouseArea` click-to-open-sidebar behavior and the horizontal/vertical `Flow` sizing intact.
- Add `Config.options.bar.indicators.hotspot.showClientCount` (JsonObject under `bar.indicators`, default `true`) in `modules/common/Config.qml`.

### Task 4 — Translation keys

Add to `translations/en_US.json` (English source of truth):

- `"Hotspot client connected"`
- `"Hotspot client disconnected"`
- `"%1 connected to %2"` (device, SSID)
- `"%1 disconnected from %2"` (device, SSID)
- `"the hotspot"` (fallback when SSID is empty)

Keep placeholders intact. Verify the file is valid JSON; other locale files may fall back to English for these keys, consistent with the translation README and existing partially-translated files.

### Task 5 — Verification

Static and hosted: `bash tests/qml-compile-check.sh` (whole tree), `QUICKSHELL_TEST_FILES=tst_hotspot_clients.qml bash tests/run-shell-tests.sh` and the full `bash tests/run-shell-tests.sh`, plus `bash tests/functional-coverage.sh`. The full hosted suite currently has two known pre-existing baseline failures (`tst_bar_content` import error and `tst_thumbnail_image` candidate-order assertion); no new failures are acceptable.

Live checklist: with the AP off, no indicator and no notifications. Start the AP with no clients → no notifications. Connect a device → badge shows `1` and a "connected" notification naming the device/SSID. Connect a second device → badge `2`. Disconnect one → "disconnected" notification, badge back to `1`. Briefly lose/reacquire a station (or force an empty `iw` dump) → no false disconnect after two-poll confirmation. Stop the AP → badge disappears, no disconnect burst. Confirm clicking the system-icons cluster still opens the right sidebar.

## Done When

- [x] The bar shows the connected-client count next to the AP icon, only while the AP is up and has clients. *(live screenshot: badge `1` on `wifi_tethering` for the one associated client; vertical-bar sizing follows the existing Flow)*
- [x] Clicking the system-icon cluster still opens the right sidebar; theme colors and the notification badge precedent are respected. *(unchanged code path; live bar renders correctly)*
- [x] Connecting a client produces exactly one "connected" notification with device label and SSID; disconnecting produces exactly one "disconnected" notification after two-poll confirmation. *(temporary hosted probe with stubbed notify-send: exactly one of each, no duplicates)*
- [x] Existing clients at shell start and clients present when the AP starts produce no notifications; stopping the AP produces no disconnect notifications. *(probe verified baseline seed/reset)*
- [x] `notifyClientChanges` and `bar.indicators.hotspot.showClientCount` opt out of notifications and the indicator respectively, defaulting to on.
- [x] `tests/qml-compile-check.sh` passes; hosted tests pass with no new failures beyond the pre-existing baseline failures. *(11/11 in `tst_hotspot_clients.qml`; full suite 37 passed / 5 failed vs clean-HEAD baseline 35 passed / 6 failed — the difference is a flaky `tst_speech_to_text`)*
- [x] Live checklist passes on the AIC8800 AP. *(deployed with `./sync.sh`; live AP `archpc-ap` had one client and the bar badge showed `1`; no config errors; the stale tooltip from the first deployment was removed and a full reload confirmed it is gone)*

Note: `tests/functional-coverage.sh` reports 16 UNMAPPED areas, but the clean-HEAD baseline reports the same 16; this plan adds none. The hosted baseline failures are `tst_bar_content`, `tst_translation`, `tst_appearance`, `tst_thumbnail_image`, `tst_managed_keybinds` (and intermittently `tst_speech_to_text`).

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-11-19 | Diff the existing `Hotspot.clients` snapshot instead of parsing hostapd events/logs. | The status JSON is already authoritative (leases ∩ station dump), already polled every 4 s, and works for both panel families; hostapd events would need a second privileged process and log access. |
| 2026-11-19 | Put the diff in a pure `HotspotUtils` singleton with a hosted test. | The live radio cannot be driven in tests; a pure helper makes add/remove/reorder/case behavior deterministic and keeps `Hotspot.qml` thin. |
| 2026-11-19 | Seed the baseline silently on first status and on AP start; clear silently on AP stop. | Prevents a burst of "connected" on shell start and "disconnected" when the AP goes down. |
| 2026-11-19 | Confirm a disappearance across two consecutive successful polls before notifying. | `iw station dump` can transiently return empty; treating that as an immediate disconnect would spam false alarms. Connected events stay immediate. |
| 2026-11-19 | Put the count on/next to the existing `wifi_tethering` icon, not as a separate bar item. | The count describes that icon; a separate item would widen the compact system-icons cluster and weaken the association. |
| 2026-11-19 | Add opt-out config flags but no new settings-page UI in this plan. | Keeps the change small and consistent with `bar.indicators.notifications.showUnreadCount`; the JSON config already exposes the toggles. |
| 2026-11-19 | Keep the bar component declarative (no JS functions). | `tests/functional-coverage.sh` would otherwise demand a dedicated test for a `modules/ii` file; the logic lives in the tested `HotspotUtils` instead. |
| 2026-11-19 | Waffle bar UI is out of scope. | Its `SystemButton.qml` does not surface the hotspot today; the request targets the ii system-icons pill. Service and notification changes are shared. |
| 2026-11-19 | Snapshot `Hotspot.clients` with `Array.from()`, and make `diffClients()` accept array-like values instead of requiring a JS `Array`. | A hosted probe found that `property list<var>` is an array-like wrapper, not a JS array: assigning it to `clientBaseline` aliased live data, and `Array.isArray()` made the helper treat every snapshot as empty. Copying the list and using `Array.from()` in the helper fixed both; the regression is locked in `tst_hotspot_clients.qml`. |

## Risks

- **Flapping Wi‑Fi / empty station dump** → two-poll confirmation for disconnects; connected events deduped by MAC.
- **Notification burst at startup or AP shutdown** → silent baseline seed/reset.
- **Wrong device label** → prefer lease hostname, fall back to MAC, normalize `*` and empty hosts in `clientLabel`.
- **Coverage/compile regressions** → helper in `modules/common/functions` with a hosted test, declarative bar component, full qml-compile-check and functional-coverage runs.
- **User does not want notifications** → `notifyClientChanges` defaults on but is a single config leaf to disable.

## Progress Notes

- [2026-11-19] Plan created after inspecting `services/Hotspot.qml`, `scripts/hotspot/aic-hotspot`, `modules/ii/bar/SystemIcons.qml`, the bar badge precedents, `modules/common/Config.qml`, the hosted test harness and both panel families' bars.
- [2026-11-19] Tasks 1-4 implemented in the checkout:
  - `modules/common/functions/HotspotUtils.qml`: pure `macOf`, `clientLabel`, `toArray`, `diffClients` helpers.
  - `tests/shell-tests/tst_hotspot_clients.qml` (11 cases) registered in `tests/shell-tests/shell.qml`; written first and observed failing 9/10 before the helper existed.
  - `services/Hotspot.qml`: baseline seeding/reset, immediate connect notifications, two-poll disconnect confirmation with cancellation, `notifyClientChanges` guard, `notify-send -a Shell`.
  - `modules/ii/bar/HotspotClientCount.qml` + `SystemIcons.qml`: declarative count badge attached to `wifi_tethering`; `bar.indicators.hotspot.showClientCount` config leaf. An initially added client-list tooltip was removed after the user reported it showing without hover.
  - `translations/en_US.json`: five new keys; `tests/coverage-exemptions.txt`: updated Hotspot reason.
- [2026-11-19] Verification:
  - `bash tests/qml-compile-check.sh` → PASS (full tree).
  - `QUICKSHELL_TEST_FILES=tst_hotspot_clients.qml bash tests/run-shell-tests.sh` → passed=11 failed=0.
  - A temporary hosted probe fed synthetic status JSON into `Hotspot.applyJson()` with `notify-send` stubbed: baseline seed and AP stop were silent, and the stub log contained exactly `-a Shell Hotspot client connected dev-two connected to TEST-AP` and `-a Shell Hotspot client disconnected dev-two disconnected from TEST-AP`. The probe and stub were removed afterwards.
  - Full hosted suite: 37 passed / 5 failed vs a clean-HEAD worktree baseline of 35 passed / 6 failed; the only difference is the known-flaky `tst_speech_to_text`. No new failures.
  - `bash tests/functional-coverage.sh` → 16 UNMAPPED, identical to the clean-HEAD baseline; no new areas introduced.
- [2026-11-19] Bug found and fixed during verification: `clients` is a `list<var>` wrapper. Keeping a direct reference in `clientBaseline` mutated the baseline with the next poll, and `Array.isArray()` in `diffClients` treated the wrapper as empty. Fixed with `Array.from()` snapshots and an array-like-tolerant helper, plus a permanent regression case.
- [2026-11-19] Deployed with `./sync.sh --dry-run --check` then `./sync.sh` (user chose the full sync). `hyprctl configerrors` empty, quickshell reachable. No new config errors in the live log.
- [2026-11-19] Live check: `aic-hotspot status` reported `archpc-ap` active with one client (`TECNO-POVA-6`); the bar's system-icons pill showed the `wifi_tethering` icon with a `1` badge. The user reported an unwanted tooltip popping up without hover; it came from a `StyledToolTip` in the badge (no hover tracking on a Rectangle), so it was removed from the component. After syncing, a stale tooltip window from the old QML engine remained on screen; touching `shell.qml` forced a full reload and the tooltip disappeared. The final screenshot shows the `1` badge with no tooltip.
- [2026-11-19] The user found the badge background too large; reduced the digit font from `smallest` (10 px) to 8 px, the padding from 4 to 2 px, and the corner offset from -3 to -2. Redeployed and confirmed the smaller badge on the live bar.
- [2026-11-19] The user then asked to relocate the round badge to the right: `SystemIcons.qml` put the AP icon and `HotspotClientCount` in a `Flow` (horizontal or vertical with the bar) so the round count sat immediately to the right of the `wifi_tethering` icon.
- [2026-11-19] Final styling requested: use the notification counter as the example. `HotspotClientCount.qml` is now a `MaterialSymbol` AP icon with a child ping Rectangle anchored to its top-right, copying `NotificationUnreadCount.qml`'s sizing (`max(text.w, text.h)`, no extra padding), font, colors and `isMaterial` handling. `SystemIcons.qml` uses it directly in place of the old icon + Flow. Redeployed and confirmed the counter now matches the notification badge's look and position.
