import QtQuick
import QtTest
import qs.modules.common

/**
 * The appearance module resolves the colour roles of the theme and owns the
 * animation tokens (durations and expressive curves) the widgets animate with.
 */
TestCase {
    id: testCase
    name: "Appearance"
    when: true

    function test_a_known_role_resolves_to_its_colour() {
        compare(String(Appearance.getColorFromName("primary")), "#cbc4cb");
        compare(String(Appearance.getColorFromName("layer0")), "#161515");
    }

    function test_the_black_role_resolves_to_the_string_black() {
        // DEFECT: every other role resolves to a colour, "black" resolves to
        // the plain string "black", so a caller that assigns it to a colour
        // property gets an invalid value. Asserted as it behaves today.
        compare(Appearance.getColorFromName("black"), "black");
    }

    function test_an_unknown_role_falls_back_to_the_primary_container() {
        compare(String(Appearance.getColorFromName("noSuchRole")), "#2d2a2f");
        compare(String(Appearance.getColorFromName("")), "#2d2a2f");
    }

    function test_the_scrim_and_the_shadow_are_translucent() {
        // The alpha is quantised to 8 bit, so it is not exactly 0.5 and 0.3.
        fuzzyCompare(Appearance.colors.colScrim.a, 0.5, 0.001);
        fuzzyCompare(Appearance.colors.colShadow.a, 0.3, 0.001);
    }

    function test_the_expressive_curves_have_the_shipped_control_points() {
        const fast = Appearance.animationCurves.expressiveFastSpatial;
        compare(fast.length, 6);
        fuzzyCompare(fast[0], 0.42, 0.0001);
        fuzzyCompare(fast[1], 1.67, 0.0001);
        fuzzyCompare(fast[2], 0.21, 0.0001);
        fuzzyCompare(fast[3], 0.90, 0.0001);

        const def = Appearance.animationCurves.expressiveDefaultSpatial;
        compare(def.length, 6);
        fuzzyCompare(def[0], 0.38, 0.0001);
        fuzzyCompare(def[1], 1.21, 0.0001);
        fuzzyCompare(def[2], 0.22, 0.0001);
        fuzzyCompare(def[3], 1.00, 0.0001);
    }

    function test_the_animation_durations_are_the_shipped_ones() {
        compare(Appearance.animationCurves.expressiveFastSpatialDuration, 350);
        compare(Appearance.animationCurves.expressiveDefaultSpatialDuration, 500);
        compare(Appearance.animationCurves.expressiveSlowSpatialDuration, 650);
        compare(Appearance.animationCurves.expressiveEffectsDuration, 200);
    }

    function test_the_element_move_animation_uses_the_default_spatial_curve() {
        compare(Appearance.animation.elementMove.duration, 500);
        compare(Appearance.animation.elementMove.type, Easing.BezierSpline);
        compare(Appearance.animation.elementMove.velocity, 650);
        compare(Appearance.animation.elementMoveFast.duration, 200);
    }
}
