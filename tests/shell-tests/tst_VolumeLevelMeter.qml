import QtQuick
import QtTest
import qs.services
import qs.modules.common.widgets

/**
 * The pavucontrol-style level meter in the volume mixer.
 *
 * Two things are worth asserting beyond "it loads": the meter must attack
 * faster than it releases (a symmetric ease reads as a slider, not a level
 * meter), and it must settle to exactly zero so the FrameAnimation ticker
 * stops instead of redrawing an idle bar forever.
 *
 * The smoothing is driven by calling step() directly — the ticker only
 * samples real pipewire peaks, which a test does not have.
 */
TestCase {
    id: testCase
    name: "VolumeLevelMeter"
    when: true

    property var meter: null

    Component {
        id: meterComponent
        VolumeLevelMeter {}
    }

    function init() {
        testCase.meter = null;
        if (meterComponent.status === Component.Ready)
            testCase.meter = meterComponent.createObject(null);
    }

    function cleanup() {
        if (testCase.meter !== null) {
            testCase.meter.destroy();
            testCase.meter = null;
        }
    }

    function test_it_loads_in_the_engine() {
        compare(meterComponent.status, Component.Ready, meterComponent.errorString());
        verify(testCase.meter !== null, "VolumeLevelMeter failed to create");
    }

    /*
     * The recreate loop: PwNodePeakMonitor's own capture stream has empty
     * properties and name "quickshell". If it is not filtered from
     * Audio.appNodes() it becomes an Input row, whose meter creates another
     * monitor, ad infinitum - and appNodeDisplayName() crashed on the empty
     * properties dict, which is why the meters were removed in the first
     * place. Assert the discriminator against both fake and real node shapes.
     */
    function test_peak_monitor_nodes_are_filtered_from_the_mixer() {
        const detector = { isStream: true, name: "quickshell", isSink: false, audio: {} };
        compare(Audio.isPeakMonitorNode(detector), true);

        const playback = { isStream: true, name: "Zen", isSink: true, audio: {} };
        compare(Audio.isPeakMonitorNode(playback), false);

        const capture = { isStream: true, name: "cava", isSink: false, audio: {} };
        compare(Audio.isPeakMonitorNode(capture), false);

        const device = { isStream: false, name: "quickshell", isSink: false, audio: {} };
        compare(Audio.isPeakMonitorNode(device), false, "a device must never be filtered");

        compare(Audio.isPeakMonitorNode(null), false);
        compare(Audio.isPeakMonitorNode(undefined), false);
    }

    function test_the_default_state_is_silent() {
        verify(testCase.meter !== null, "the meter did not create");
        compare(testCase.meter.level, 0);
        compare(testCase.meter.peakHold, 0);
        compare(testCase.meter.target, 0);
        compare(testCase.meter.muted, false);
    }

    function test_a_peak_raises_the_target_but_never_past_one() {
        verify(testCase.meter !== null, "the meter did not create");
        testCase.meter.peak = 0.5;
        compare(testCase.meter.target, 0.5);
        testCase.meter.peak = 7; // a nonsense peak must not overflow the bar
        compare(testCase.meter.target, 1);
    }

    function test_muting_forces_a_silent_target() {
        verify(testCase.meter !== null, "the meter did not create");
        testCase.meter.peak = 0.8;
        compare(testCase.meter.target, 0.8);
        testCase.meter.muted = true;
        compare(testCase.meter.target, 0);
    }

    function test_it_attacks_faster_than_it_releases() {
        verify(testCase.meter !== null, "the meter did not create");
        // One frame of a full-scale peak
        testCase.meter.peak = 1;
        testCase.meter.step(1 / 60);
        const afterAttack = testCase.meter.level;
        verify(afterAttack > 0.3, `attack too slow: ${afterAttack}`);

        // The same frame length with no signal must move less far down
        testCase.meter.peak = 0;
        testCase.meter.step(1 / 60);
        const afterRelease = testCase.meter.level;
        verify(afterRelease < afterAttack, "release must fall below the attacked level");
        verify(afterAttack - afterRelease < (afterAttack - 0) * 0.5,
            `release too fast: ${afterAttack} -> ${afterRelease}`);
    }

    function test_the_peak_hold_holds_then_falls() {
        verify(testCase.meter !== null, "the meter did not create");
        testCase.meter.peak = 1;
        for (let i = 0; i < 10; i++) testCase.meter.step(1 / 60);
        const held = testCase.meter.peakHold;
        verify(held > 0.5, `peak hold never engaged: ${held}`);

        // Signal gone: during the hold window the marker stays put
        testCase.meter.peak = 0;
        testCase.meter.step(1 / 60);
        compare(testCase.meter.peakHold, held);

        // After the hold expires it decays toward the live level
        for (let i = 0; i < 80; i++) testCase.meter.step(1 / 60);
        verify(testCase.meter.peakHold < held, "the peak hold never fell");
    }

    function test_it_settles_exactly_to_zero() {
        verify(testCase.meter !== null, "the meter did not create");
        testCase.meter.peak = 0.9;
        for (let i = 0; i < 10; i++) testCase.meter.step(1 / 60);
        testCase.meter.peak = 0;
        for (let i = 0; i < 600; i++) testCase.meter.step(1 / 60);
        // Exact, not merely small: the ticker binding stops on === 0
        compare(testCase.meter.level, 0);
        compare(testCase.meter.peakHold, 0);
        compare(testCase.meter.holdTimer, 0);
    }

    function test_the_fill_ramps_to_the_error_colour_near_clipping() {
        verify(testCase.meter !== null, "the meter did not create");
        const base = testCase.meter.fillColor;
        testCase.meter.level = 0.4;
        compare(testCase.meter.fillColor, testCase.meter.highlightColor,
            "a quiet level must keep the primary fill");
        testCase.meter.level = 1;
        verify(testCase.meter.fillColor !== testCase.meter.highlightColor,
            "a full-scale level must ramp toward the error colour");
    }
}
