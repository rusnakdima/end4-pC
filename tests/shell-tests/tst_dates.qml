import QtQuick
import QtTest
import qs.modules.common.functions

/**
 * Tests for the date helpers.
 *
 * The helpers work on the local calendar, so the assertions compare
 * the calendar fields (year, month, day) and never the timestamp.
 * The reference date is a Monday, the 15th of January 2024.
 */
TestCase {
    id: testCase
    name: "Dates"
    when: true

    // The 15th of January 2024 is a Monday.
    readonly property var monday: new Date(2024, 0, 15)

    // The 14th of January 2024 is a Sunday.
    readonly property var sunday: new Date(2024, 0, 14)

    function test_get_first_day_of_week_with_monday_as_the_first_day() {
        const result = DateUtils.getFirstDayOfWeek(monday, 1);
        compare(result.getFullYear(), 2024);
        compare(result.getMonth(), 0);
        compare(result.getDate(), 15);
    }

    function test_get_first_day_of_week_with_sunday_as_the_first_day() {
        const result = DateUtils.getFirstDayOfWeek(monday, 0);
        compare(result.getFullYear(), 2024);
        compare(result.getMonth(), 0);
        compare(result.getDate(), 14);
    }

    function test_get_first_day_of_week_defaults_to_monday() {
        const result = DateUtils.getFirstDayOfWeek(monday);
        compare(result.getDate(), 15);
    }

    function test_get_first_day_of_week_of_a_sunday_goes_back_to_the_monday() {
        const result = DateUtils.getFirstDayOfWeek(sunday, 1);
        compare(result.getMonth(), 0);
        compare(result.getDate(), 8);
    }

    function test_get_first_day_of_week_rolls_over_the_month_boundary() {
        // The 1st of January 2024 is a Monday, so with Sunday as the
        // first day the week starts in December 2023.
        const result = DateUtils.getFirstDayOfWeek(new Date(2024, 0, 1), 0);
        compare(result.getFullYear(), 2023);
        compare(result.getMonth(), 11);
        compare(result.getDate(), 31);
    }

    function test_get_first_day_of_week_does_not_change_the_input() {
        const before = monday.getTime();
        DateUtils.getFirstDayOfWeek(monday, 1);
        compare(monday.getTime(), before);
    }

    function test_get_ith_day_date_of_same_week() {
        // With Monday as the first day the week of the reference date
        // runs from the 15th to the 21st.
        const first = DateUtils.getIthDayDateOfSameWeek(monday, 0, 1);
        compare(first.getMonth(), 0);
        compare(first.getDate(), 15);

        const last = DateUtils.getIthDayDateOfSameWeek(monday, 6, 1);
        compare(last.getMonth(), 0);
        compare(last.getDate(), 21);
    }

    function test_get_ith_day_date_of_same_week_with_sunday_as_the_first_day() {
        const first = DateUtils.getIthDayDateOfSameWeek(monday, 0, 0);
        compare(first.getMonth(), 0);
        compare(first.getDate(), 14);

        const last = DateUtils.getIthDayDateOfSameWeek(monday, 6, 0);
        compare(last.getMonth(), 0);
        compare(last.getDate(), 20);
    }

    function test_same_date_is_true_for_the_same_calendar_day() {
        verify(DateUtils.sameDate(monday, new Date(2024, 0, 15, 23, 59)));
        verify(DateUtils.sameDate(monday, new Date(2024, 0, 15, 0, 0)));
        verify(DateUtils.sameDate(monday, monday));
    }

    function test_same_date_is_false_for_a_different_day() {
        verify(!DateUtils.sameDate(monday, sunday));
        verify(!DateUtils.sameDate(monday, new Date(2024, 1, 15)));
        verify(!DateUtils.sameDate(monday, new Date(2023, 0, 15)));
    }
}
