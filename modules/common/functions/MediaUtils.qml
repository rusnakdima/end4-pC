pragma Singleton

import Quickshell

/**
 * Pure playback-sync helpers for the wallpaper media surfaces.
 *
 * Every surface follows the shared WallpaperVideo clock, but a decoder that
 * is behind by a few frames is healthy — seeking it again on every clock tick
 * makes it drop to keyframes and look frozen. A seek is only worth its cost on
 * join, on a clip/epoch change, or when the drift is gross and has persisted.
 */
Singleton {
    id: root

    // A decoder is allowed to lag by half a second before it is corrected.
    readonly property int seekThresholdMs: 500
    // Never seek the same decoder twice inside this window.
    readonly property int seekCooldownMs: 3000

    /**
     * Whether a surface should seek to the group position right now.
     * `force` is used on join / clip change / restart, where an immediate seek
     * is wanted even inside the cooldown.
     */
    function shouldSeek(position: int, target: real, duration: int, now: real,
                        lastSeekAt: real, active: bool, force: bool): bool {
        if (!active || target < 0 || duration <= 0) return false;
        if (force) return true;
        if (now - lastSeekAt < root.seekCooldownMs) return false;
        const drift = Math.abs(position - target);
        // Near the loop seam a large drift is just the wrap, not a stall.
        if (drift <= root.seekThresholdMs || drift >= duration - root.seekThresholdMs) return false;
        return true;
    }
}
