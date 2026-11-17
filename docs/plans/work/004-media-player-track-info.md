# Media player: restore track title and artist

> The media player card (bar popup) and the sidebar media card render album art, time and controls but no track title or artist — the two text elements were dropped in the lyrics removal. Restore them.

**Status**: Completed
**Created**: 2026-11-17
**Owner**: general

## Goal

1. The media controls popup (left-click the bar media widget, `GlobalStates.mediaControlsOpen`, IPC `mediaControls.toggle/open`) shows the **track title** and **artist** above the time/progress row for every listed player.
2. The sidebar-right media card (same `Player` component) shows them too.
3. Missing metadata falls back to `Unknown Title` / `Unknown Artist`, never to an empty line.
4. No visual regression: album art, time, progress bar, previous/play-pause/next and the hover volume dial keep their current position and behavior.

## Context

### Root cause

- `modules/common/widgets/PlayerContent.qml` is the shared content of the media card used by `Player.qml` (`Player.qml:198`).
- Commit `b0e222b` (*feat(ii): Waffle panel family replaces DynamicIsland…*) removed the lyrics feature. The same diff deleted the `trackTitle` and `trackArtist` `StyledText` blocks from `PlayerContent.qml` (see `git show b0e222b -- modules/common/widgets/PlayerContent.qml`, hunk `@@ -157,64 +131,10 @@`).
- Today the file has **no** binding for `trackTitle` / `trackArtist` at all; only `trackTime` remains (`PlayerContent.qml:134-143`). That is exactly the symptom: art, time, controls show, title/artist do not.

### The MPRIS data is fine (verified live, 2026-11-17)

- Session bus player: `org.mpris.MediaPlayer2.YoutubeMusic`, paused, `trackTitle="Enough (I DON’T FOLD)"`, `trackArtist="Echoes and Scars"`, album art URL present.
- A standalone Quickshell 0.3.2 probe printed the same values from `Quickshell.Services.Mpris` directly.
- A probe that copied the real `services/MprisController.qml` (with stub `Config`/`Translation`) printed `activePlayer=org.mpris.MediaPlayer2.YoutubeMusic`, `activeTrack.title="Enough (I DON’T FOLD)"`, `activeTrack.artist="Echoes and Scars"`.
- `services/MprisController.qml:115-121` normalization and `services/qmldir` registration are therefore not the problem. `tests/shell-tests/tst_mpris.qml` passes 7/7.

### Affected surfaces

- `modules/ii/mediaControls/MediaControls.qml:198` — delegate `Player {}` inside the popup; opened from `modules/ii/bar/Media.qml:103` (`mediaControlsOpen`) and the `mediaControls` IpcHandler (`MediaControls.qml:280-303`).
- `modules/ii/sidebarRight/SidebarRightContent.qml:585` — media section `Player {}`.
- Both go through `Player.qml:198-203` → `PlayerContent`.
- Not affected: Waffle action-center media card (`modules/waffle/actionCenter/MediaPaneContent.qml:86,92`) binds `activePlayer.trackTitle/trackArtist` directly and already works.

### Layout target (lyrics-free)

The removed blocks used `root.lyricsTitleY`, which no longer exists. Restore the simple pre-lyrics placement:

- title: `x: root.textX`, `y: root.pad` (13), `width: root.textWidth`, `Appearance.font.pixelSize.large`, `colOnLayer0`, `elide: Text.ElideRight`, `animateChange: true`
- artist: same `x`/`width`, `y: trackTitle.y + trackTitle.implicitHeight + 2`, `Appearance.font.pixelSize.smaller`, `colSubtext`, `elide: Text.ElideRight`, `animateChange: true`
- keep `trackTime` at `root.rowY - height - 5` untouched (`PlayerContent.qml:137`).

## Constraints

- Change only `modules/common/widgets/PlayerContent.qml`; do not touch `MprisController` or the player service.
- Use `StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Unknown Title")` and `root.player?.trackArtist || Translation.tr("Unknown Artist")` — both keys already exist in `translations/en_US.json` (lines 8 and 139), so the exact key-count assertion `1814` in `tests/shell-tests/tst_translation.qml:72` must not change.
- No new JavaScript `function` declarations in `modules/common/widgets/**` (keeps `tests/functional-coverage.sh` at its baseline).
- Text must elide inside `root.textWidth` (card width 440, art column 114 + pads, sidebar card narrower) and must not overlap `trackTime` or the control rows.

## Tasks

| # | Task | Agent | Priority | Status | Dependencies |
|---|------|-------|----------|--------|--------------|
| 1 | Plan artifacts: this file + `.agents/results/plan-*.json` | general | 1 | DONE | — |
| 2 | Re-add `trackTitle` + `trackArtist` `StyledText` blocks in `PlayerContent.qml` | frontend | 1 | DONE | 1 |
| 3 | Verification: compile check, shell-test baseline, live smoke of both cards | qa | 2 | DONE | 2 |
| 4 | Commit the fix (conventional message) | general | 2 | DONE | 3 |

### Gate results (baselines recorded 2026-11-17, before the fix)

- `tests/qml-compile-check.sh` on `services/MprisController.qml`, `MediaPaneContent.qml`, `MediaControls.qml`, `Media.qml` → **PASS**.
- `tests/run-shell-tests.sh` → **35 passed / 2 failed / 37 total** (pre-existing: `tst_bar_content`, `tst_thumbnail_image`).
- `tst_mpris.qml` → **7/7 passed** with the live player.

## Done When

- [x] Media controls popup shows title and artist for the live player.
- [x] Sidebar-right media card shows title and artist when `sidebar.mediaPlayer` is enabled (default false; it is hidden on this machine, and it uses the same verified `PlayerContent` component).
- [x] Both texts elide instead of pushing/clipping the time or control rows.
- [x] Empty metadata shows `Unknown Title` / `Unknown Artist`.
- [x] `tests/qml-compile-check.sh modules/common/widgets/PlayerContent.qml` → PASS.
- [x] `tests/run-shell-tests.sh` → 35 passed / 2 failed (same two pre-existing files, no new failure).
- [x] No change to `translations/en_US.json` and `tst_translation.qml` key count.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-11-17 | Restore the text elements inside `PlayerContent.qml` rather than in each `Player` caller | One shared component serves both the popup and the sidebar card; duplicating the bindings would drift. |
| 2026-11-17 | Use `Unknown Title`/`Unknown Artist` (not the old `Untitled`) | Same wording as the Waffle media card and the MPRIS controller; both keys already exist, so the translation-count test is unaffected. |
| 2026-11-17 | Keep the lyrics-free two-line layout | The lyrics mode and its `lyricsTitleY` are gone; the simple top-left placement fits the 160 px card above `trackTime`. |

## Progress Notes

- [2026-11-17] Plan created after a live MPRIS probe and `git show b0e222b` located the regression.

- [2026-11-17] Implemented in `modules/common/widgets/PlayerContent.qml`: re-added `import qs.services` (removed with the lyrics feature, needed for `Translation`) and the `trackTitle`/`trackArtist` `StyledText` blocks above `trackTime`. Only that file changed.
- [2026-11-17] Gates: `tests/qml-compile-check.sh` (tree) → PASS; `tests/run-shell-tests.sh` → 35 passed / 2 failed / 37 (same `tst_bar_content`, `tst_thumbnail_image`); `tests/functional-coverage.sh` → the same 16 pre-existing UNMAPPED areas.
- [2026-11-17] Live verification on the running shell (synced with `./sync.sh --force`, session unlocked and no lock layer on screen): the media controls popup rendered `Enough (I DON’T FOLD)` / `Echoes and Scars` above `2:04 / 3:36`, with art and controls unchanged; both panels were closed afterwards.
- [2026-11-17] Note: the first popup opened immediately after the rsync sync still showed the old card. Copying the file again and toggling the popup rendered the new text; if a future sync shows a stale card, toggle the panel or restart the shell before concluding the fix failed.
- [2026-11-17] `sidebar.mediaPlayer` is `false` in the live `~/.config/illogical-impulse/config.json`, so the sidebar media card is not rendered on this machine; it shares `Player` → `PlayerContent` with the popup and needs no separate code change. The popup was used for the visual proof.
