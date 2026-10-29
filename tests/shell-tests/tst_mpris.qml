import QtQuick
import QtTest
import qs.services
import qs.modules.common

/**
 * Tests for the MPRIS controller.
 *
 * The service exposes the metadata of the active player as `activeTrack`,
 * a plain record with uniqueId/artUrl/title/artist/album. The normalisation
 * rule of the service is: a missing value is replaced by the translated
 * "Unknown ..." label, never by an empty string.
 *
 * Whether a media player is running on the session bus depends on the
 * machine, so the metadata assertions compare against the player that is
 * actually there - the normalisation rule holds in both cases. The
 * duplicate filtering (`isRealPlayer`) works on a raw MPRIS record, so it is
 * exercised with hand built player records.
 */
TestCase {
    id: testCase
    name: "Mpris"
    when: true

    // The duplicate filtering of the service is driven by the config, which
    // is read asynchronously.
    function waitForConfig() {
        let tries = 0;
        while (!Config.ready && tries < 50) {
            wait(100);
            tries++;
        }
        return Config.ready;
    }

    function test_the_service_reports_the_absence_of_a_player() {
        const players = MprisController.players;

        if (players.length === 0) {
            // No player on the bus: the service reports an empty player.
            compare(MprisController.activePlayer, null);
            compare(MprisController.trackedPlayer, null);
            MprisController.updateTrack();
            compare(MprisController.activeTrack.title, Translation.tr("Unknown Title"));
            compare(MprisController.activeTrack.artist, Translation.tr("Unknown Artist"));
            compare(MprisController.activeTrack.album, Translation.tr("Unknown Album"));
            compare(MprisController.activeTrack.artUrl, "");
        } else {
            // A player is running: the service tracks one of them.
            verify(MprisController.activePlayer !== null);
        }
    }

    function test_the_metadata_is_normalised_into_the_active_track() {
        MprisController.updateTrack();

        const player = MprisController.activePlayer;
        const track = MprisController.activeTrack;

        compare(track.title, (player?.trackTitle) || Translation.tr("Unknown Title"));
        compare(track.artist, (player?.trackArtist) || Translation.tr("Unknown Artist"));
        compare(track.album, (player?.trackAlbum) || Translation.tr("Unknown Album"));
        compare(track.artUrl, player?.trackArtUrl ?? "");
        verify(track.title.length > 0);
        verify(track.artist.length > 0);
    }

    function test_the_capabilities_follow_the_active_player() {
        const player = MprisController.activePlayer;

        compare(MprisController.canTogglePlaying, player?.canTogglePlaying ?? false);
        compare(MprisController.canGoPrevious, player?.canGoPrevious ?? false);
        compare(MprisController.canGoNext, player?.canGoNext ?? false);
        compare(MprisController.hasShuffle, player?.shuffle ?? false);
        verify(!MprisController.shuffleSupported || player?.shuffleSupported === true);
        verify(!MprisController.loopSupported || player?.loopSupported === true);
    }

    function test_is_real_player_keeps_a_regular_player() {
        compare(MprisController.isRealPlayer({ dbusName: "org.mpris.MediaPlayer2.vlc.instance9137" }), true);
        compare(MprisController.isRealPlayer({ dbusName: "org.mpris.MediaPlayer2.mpv" }), true);
    }

    function test_is_real_player_drops_the_playerctld_duplicate() {
        verify(waitForConfig());
        // playerctld only mirrors other buses, so it is filtered out - but only
        // when the duplicate filtering is actually enabled in the config.
        const filtering = Config.options.media.filterDuplicatePlayers;
        compare(MprisController.isRealPlayer({ dbusName: "org.mpris.MediaPlayer2.playerctld.instance1337" }), !filtering);
    }

    function test_is_real_player_keeps_the_non_instance_mpd_bus() {
        verify(waitForConfig());
        const filtering = Config.options.media.filterDuplicatePlayers;
        compare(MprisController.isRealPlayer({ dbusName: "org.mpris.MediaPlayer2.MediaPlayer2.mpd" }), true);
        compare(MprisController.isRealPlayer({ dbusName: "org.mpris.MediaPlayer2.gnome-mpd.mpd" }), !filtering);
    }
}
