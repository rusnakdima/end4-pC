import QtQuick
import QtTest
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * The wallpaper video must follow one shared clock without seeking a healthy
 * decoder on every tick, and it must restart when the theme/shell restarts.
 */
TestCase {
    id: testCase
    name: "WallpaperVideo"
    when: true

    // Panel previews must reuse the poster instead of opening a second
    // decoder for the clip that is already playing on the desktop.
    WallpaperMedia {
        id: stillOnly
        source: "/tmp/wallpaper-video-not-a-real-file.mp4"
        allowLive: false
        showStill: false
    }

    function test_a_poster_only_surface_never_decodes() {
        compare(stillOnly.wantsVideo, false);
        verify(!stillOnly.videoReady);
        compare(stillOnly.playbackPath, "");
    }

    function test_small_drift_is_left_alone() {
        // A decoder a few frames behind is normal. Seeking it every 100 ms is
        // what froze the clip on the desktop and in every preview.
        verify(!MediaUtils.shouldSeek(1000, 1200, 10000, 10000, 0, true, false));
    }

    function test_gross_drift_is_corrected_after_the_cooldown() {
        verify(MediaUtils.shouldSeek(1000, 5000, 10000, 10000, 1000, true, false));
    }

    function test_gross_drift_is_not_corrected_inside_the_cooldown() {
        verify(!MediaUtils.shouldSeek(1000, 5000, 10000, 2000, 0, true, false));
    }

    function test_the_loop_seam_is_not_a_drift() {
        // position 9900ms, target 100ms of a 10s clip: the loop will wrap.
        verify(!MediaUtils.shouldSeek(9900, 100, 10000, 10000, 0, true, false));
    }

    function test_an_inactive_or_unknown_target_is_never_seeked() {
        verify(!MediaUtils.shouldSeek(1000, 5000, 10000, 10000, 0, false, false));
        verify(!MediaUtils.shouldSeek(1000, -1, 10000, 10000, 0, true, false));
        verify(!MediaUtils.shouldSeek(1000, 5000, 0, 10000, 0, true, false));
    }

    function test_a_join_or_restart_seeks_immediately() {
        verify(MediaUtils.shouldSeek(0, 5000, 10000, 100, 0, true, true));
    }

    function test_restart_resets_the_shared_clock() {
        WallpaperVideo.desktopElapsed = 12345;
        WallpaperVideo.lockElapsed = 6789;
        WallpaperVideo.restart();
        compare(WallpaperVideo.desktopElapsed, 0);
        compare(WallpaperVideo.lockElapsed, 0);
    }

    // A surface that goes off screen and comes back must reuse the proxy it
    // already prepared. Blanketing playbackPath on every activation makes the
    // clip fall back to the still for the whole encode, which looks like a
    // multi-second freeze on the desktop.
    WallpaperMedia {
        id: reactivated
        source: "/tmp/reactivation-test.mp4"
        allowLive: false
        useProxy: false
        showStill: false
        playbackPath: "/tmp/reactivation-proxy.mp4"
    }

    function test_reactivation_keeps_a_ready_playback_path() {
        // The proxy already resolved this exact source. A reactivation must
        // not blank the path while a new encode is prepared.
        reactivated.resolvedSource = reactivated.source;
        reactivated.playbackPath = "/tmp/reactivation-proxy.mp4";
        reactivated.updateProxy();
        compare(reactivated.playbackPath, "/tmp/reactivation-proxy.mp4");
    }
}
