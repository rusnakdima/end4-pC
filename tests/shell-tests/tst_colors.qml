import QtQuick
import QtTest
import qs.modules.common.functions

/**
 * Tests for the colour helpers.
 *
 * The getters of a QML colour (r, g, b, a) are floats in the range
 * 0..1, and the helpers here work on that scale. Every channel
 * assertion therefore uses a tolerance: the colours are quantised to
 * 8 bits per channel internally, so 0.5 comes back as 0.5000076.
 */
TestCase {
    id: testCase
    name: "Colors"
    when: true

    // Compares two channel values with a tolerance that covers the
    // 8 bit quantisation of a colour.
    function verifyClose(actual, expected, delta) {
        verify(Math.abs(actual - expected) <= (delta === undefined ? 0.01 : delta),
            "expected " + expected + " (+/- " + (delta === undefined ? 0.01 : delta) + "), got " + actual);
    }

    function test_hex_parsing_of_a_six_digit_colour() {
        const c = Qt.color("#ff0000");
        compare(c.r, 1);
        compare(c.g, 0);
        compare(c.b, 0);
        compare(c.a, 1);
    }

    function test_hex_parsing_of_a_mid_grey() {
        // 0x60 is 96, and 96 / 255 is 0.3764706.
        const c = Qt.color("#606060");
        verifyClose(c.r, 96 / 255, 0.002);
        verifyClose(c.g, 96 / 255, 0.002);
        verifyClose(c.b, 96 / 255, 0.002);
    }

    function test_hex_parsing_of_a_three_digit_colour() {
        // "#abc" expands to "#aabbcc", so the red channel is 0xaa.
        const c = Qt.color("#abc");
        verifyClose(c.r, 170 / 255, 0.002);
        verifyClose(c.g, 187 / 255, 0.002);
        verifyClose(c.b, 204 / 255, 0.002);
    }

    function test_an_invalid_colour_name_throws() {
        let threw = false;
        try {
            Qt.color("notacolor");
        } catch (e) {
            threw = true;
        }
        verify(threw);
    }

    function test_transparentize_scales_the_alpha_channel() {
        const c = ColorUtils.transparentize("#ff0000", 0.5);
        verifyClose(c.a, 0.5);
        // The colour channels are untouched.
        compare(c.r, 1);
        compare(c.g, 0);
        compare(c.b, 0);
    }

    function test_transparentize_of_a_fully_opaque_colour_at_the_boundaries() {
        compare(ColorUtils.transparentize("#ff0000", 1).a, 0);
        compare(ColorUtils.transparentize("#ff0000", 0).a, 1);
        // A percentage above 1 makes the alpha negative, and the colour
        // is clamped to 0. A negative percentage makes it larger than 1
        // and the colour is clamped to 1.
        compare(ColorUtils.transparentize("#ff0000", 1.5).a, 0);
        compare(ColorUtils.transparentize("#ff0000", -1).a, 1);
    }

    function test_transparentize_scales_the_alpha_of_the_input() {
        // An input that already carries an alpha of 0.5 ends up at
        // 0.25 when it is transparentized by 50 percent.
        verifyClose(ColorUtils.transparentize(Qt.rgba(1, 0, 0, 0.5), 0.5).a, 0.25);
    }

    function test_transparentize_defaults_to_fully_transparent() {
        compare(ColorUtils.transparentize("#ff0000").a, 0);
    }

    function test_mix_percentage_one_is_the_first_colour() {
        const c = ColorUtils.mix("#ff0000", "#0000ff", 1);
        compare(c.r, 1);
        compare(c.g, 0);
        compare(c.b, 0);
    }

    function test_mix_percentage_zero_is_the_second_colour() {
        const c = ColorUtils.mix("#ff0000", "#0000ff", 0);
        compare(c.r, 0);
        compare(c.g, 0);
        compare(c.b, 1);
    }

    function test_mix_of_two_opaque_colours_in_the_middle() {
        const c = ColorUtils.mix("#ff0000", "#0000ff", 0.5);
        verifyClose(c.r, 0.5);
        verifyClose(c.g, 0);
        verifyClose(c.b, 0.5);
        verifyClose(c.a, 1);
    }

    function test_mix_defaults_to_half() {
        verifyClose(ColorUtils.mix("#ff0000", "#0000ff").r, 0.5);
    }

    function test_mix_mixes_the_alpha_channel_as_well() {
        const c = ColorUtils.mix(Qt.rgba(1, 0, 0, 0.5), Qt.rgba(0, 0, 1, 0.25), 0.5);
        verifyClose(c.a, 0.375);
    }

    function test_is_dark_uses_the_hsl_lightness() {
        verify(ColorUtils.isDark("#000000"));
        verify(ColorUtils.isDark("#7f7f7f"));
        verify(!ColorUtils.isDark("#808080"));
        verify(!ColorUtils.isDark("#ffffff"));
    }

    function test_clamp01_clamps_to_the_unit_interval() {
        compare(ColorUtils.clamp01(-1), 0);
        compare(ColorUtils.clamp01(0), 0);
        compare(ColorUtils.clamp01(0.5), 0.5);
        compare(ColorUtils.clamp01(1), 1);
        compare(ColorUtils.clamp01(2), 1);
    }

    function test_clamp01_of_nan_is_nan() {
        verify(isNaN(ColorUtils.clamp01(NaN)));
    }

    function test_apply_alpha_sets_and_clamps_the_alpha() {
        verifyClose(ColorUtils.applyAlpha("#ff0000", 0.25).a, 0.25);
        compare(ColorUtils.applyAlpha("#ff0000", 2).a, 1);
        compare(ColorUtils.applyAlpha("#ff0000", -1).a, 0);
        // The colour channels are untouched.
        compare(ColorUtils.applyAlpha("#ff0000", 0.5).r, 1);
    }

    function test_solve_overlay_color_round_trips() {
        const base = "#202020";
        const target = "#606060";
        const overlay = ColorUtils.solveOverlayColor(base, target, 0.5);
        // The solved overlay is (target - base * 0.5) / 0.5.
        verifyClose(overlay.r, 0.627451, 0.002);
        verifyClose(overlay.a, 0.5);
        // Mixing the solved overlay over the base yields the target.
        const back = ColorUtils.mix(overlay, base, 0.5);
        verifyClose(back.r, 96 / 255, 0.002);
        verifyClose(back.g, 96 / 255, 0.002);
        verifyClose(back.b, 96 / 255, 0.002);
    }

    function test_solve_overlay_color_with_zero_opacity_saturates() {
        // Dividing by an opacity of zero gives an infinity, which is
        // clamped to 1, and the alpha of the result is the opacity.
        const overlay = ColorUtils.solveOverlayColor("#000000", "#808080", 0);
        compare(overlay.r, 1);
        compare(overlay.g, 1);
        compare(overlay.b, 1);
        compare(overlay.a, 0);
    }

    function test_color_with_hue_of_takes_the_hue_of_the_second_colour() {
        const c = ColorUtils.colorWithHueOf("#ff0000", "#0000ff");
        verifyClose(c.hsvHue, 240 / 360, 0.002);
        verifyClose(c.r, 0);
        verifyClose(c.g, 0);
        verifyClose(c.b, 1);
    }

    function test_color_with_hue_of_a_grey_source_turns_white() {
        // A grey has no hue, its hsvHue is -1, and Qt.hsva with a
        // negative hue comes back as white.
        const c = ColorUtils.colorWithHueOf("#ff0000", "#808080");
        verifyClose(c.r, 1);
        verifyClose(c.g, 1);
        verifyClose(c.b, 1);
    }

    function test_color_with_saturation_of_takes_the_saturation_of_the_second_colour() {
        const c = ColorUtils.colorWithSaturationOf("#ff8000", "#808080");
        // The hue and the value stay with the first colour, the
        // saturation of the grey is 0.
        verifyClose(c.hsvHue, 30 / 360, 0.002);
        verifyClose(c.hsvSaturation, 0, 0.002);
        verifyClose(c.hsvValue, 1, 0.002);
    }

    function test_color_with_lightness_sets_the_lightness() {
        const c = ColorUtils.colorWithLightness("#ff8000", 0.25);
        verifyClose(c.hslLightness, 0.25);
        verifyClose(c.hslHue, 30 / 360, 0.002);
        verifyClose(c.hslSaturation, 1, 0.002);
    }

    function test_color_with_lightness_of_takes_the_lightness_of_the_second_colour() {
        const c = ColorUtils.colorWithLightnessOf("#ff8000", "#808080");
        verifyClose(c.hslLightness, 128 / 255, 0.002);
        verifyClose(c.hslHue, 30 / 360, 0.002);
    }

    function test_adapt_to_accent_keeps_the_lightness_of_the_base() {
        const c = ColorUtils.adaptToAccent("#ff8000", "#0000ff");
        verifyClose(c.hslHue, 240 / 360, 0.002);
        verifyClose(c.hslSaturation, 1, 0.002);
        verifyClose(c.hslLightness, 0.5, 0.002);
    }

    function test_the_helpers_keep_every_channel_inside_zero_to_one() {
        const results = [
            ColorUtils.mix("#ff0000", "#0000ff", 0.5),
            ColorUtils.transparentize("#ff0000", 0.5),
            ColorUtils.applyAlpha("#ff0000", 0.5),
            ColorUtils.solveOverlayColor("#202020", "#606060", 0.5),
            ColorUtils.colorWithHueOf("#ff0000", "#0000ff"),
            ColorUtils.colorWithSaturationOf("#ff0000", "#0000ff"),
            ColorUtils.colorWithLightness("#ff0000", 0.25),
            ColorUtils.adaptToAccent("#ff0000", "#0000ff")
        ];
        for (let i = 0; i < results.length; ++i) {
            const c = results[i];
            verify(c.r >= 0 && c.r <= 1);
            verify(c.g >= 0 && c.g <= 1);
            verify(c.b >= 0 && c.b <= 1);
            verify(c.a >= 0 && c.a <= 1);
        }
    }
}
