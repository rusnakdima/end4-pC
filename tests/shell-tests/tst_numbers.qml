import QtQuick
import QtTest
import qs.modules.common.functions

/**
 * Tests for the number helpers.
 *
 * NumberUtils only exposes roundToEven, so this file pins that one
 * function down exactly: how it rounds, what it does with negative
 * values, with half values and with input that is not a number at all.
 */
TestCase {
    id: testCase
    name: "Numbers"
    when: true

    function test_round_to_even_of_integers() {
        compare(NumberUtils.roundToEven(0), 0);
        compare(NumberUtils.roundToEven(1), 2);
        compare(NumberUtils.roundToEven(2), 2);
        compare(NumberUtils.roundToEven(3), 4);
        compare(NumberUtils.roundToEven(4), 4);
        compare(NumberUtils.roundToEven(5), 6);
        compare(NumberUtils.roundToEven(7), 8);
        compare(NumberUtils.roundToEven(9), 10);
    }

    function test_round_to_even_of_negative_integers() {
        compare(NumberUtils.roundToEven(-1), 0);
        compare(NumberUtils.roundToEven(-2), -2);
        compare(NumberUtils.roundToEven(-3), -2);
        compare(NumberUtils.roundToEven(-4), -4);
        compare(NumberUtils.roundToEven(-5), -4);
    }

    function test_round_to_even_of_half_values() {
        // Math.round rounds a half up, so 0.5 lands on 0 and 1.5 on 2.
        compare(NumberUtils.roundToEven(0.5), 0);
        compare(NumberUtils.roundToEven(1.5), 2);
        compare(NumberUtils.roundToEven(2.5), 2);
        compare(NumberUtils.roundToEven(3.5), 4);
        compare(NumberUtils.roundToEven(4.5), 4);
        compare(NumberUtils.roundToEven(5.5), 6);
    }

    function test_round_to_even_of_negative_half_values() {
        // Math.round rounds -0.75 down to -1, so the result stays even.
        compare(NumberUtils.roundToEven(-0.5), 0);
        compare(NumberUtils.roundToEven(-1.5), -2);
        compare(NumberUtils.roundToEven(-2.5), -2);
        compare(NumberUtils.roundToEven(-3.5), -4);
    }

    function test_round_to_even_of_a_non_numeric_string_is_nan() {
        // "abc" / 2 is NaN and NaN stays NaN: the helper does not throw
        // and does not fall back to a default.
        verify(isNaN(NumberUtils.roundToEven("abc")));
        verify(isNaN(NumberUtils.roundToEven(undefined)));
        verify(isNaN(NumberUtils.roundToEven(NaN)));
    }

    function test_round_to_even_of_null_is_zero() {
        // null is coerced to 0 by the division, so the result is 0 and
        // not NaN. This is the one non numeric input that does not
        // produce NaN.
        compare(NumberUtils.roundToEven(null), 0);
    }

    function test_round_to_even_of_a_numeric_string_is_coerced() {
        compare(NumberUtils.roundToEven("4"), 4);
        compare(NumberUtils.roundToEven("5"), 6);
    }

    function test_round_to_even_of_a_boolean_or_an_array() {
        // true / 2 is 0.5, [1] / 2 is 0.5 as well.
        compare(NumberUtils.roundToEven(true), 2);
        compare(NumberUtils.roundToEven(false), 0);
        compare(NumberUtils.roundToEven([1]), 2);
    }

    function test_round_to_even_of_infinity_is_infinity() {
        verify(NumberUtils.roundToEven(Infinity) === Infinity);
        verify(!isFinite(NumberUtils.roundToEven(Infinity)));
    }

    function test_round_to_even_of_minus_one_is_negative_zero() {
        // Math.round(-0.5) is -0, so the result of roundToEven(-1) is -0
        // and not 0. It compares equal to 0, but Object.is tells them
        // apart.
        verify(NumberUtils.roundToEven(-1) === 0);
        verify(Object.is(NumberUtils.roundToEven(-1), -0));
    }

    function test_round_to_even_always_returns_an_even_integer() {
        const values = [0, 1, 2, 3, 7, 13, 0.5, 2.5, -1, -3, -2.5];
        for (let i = 0; i < values.length; ++i) {
            const result = NumberUtils.roundToEven(values[i]);
            verify(result % 2 === 0);
            verify(result === Math.round(values[i] / 2) * 2);
        }
    }
}
