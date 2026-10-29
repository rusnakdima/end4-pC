import QtQuick
import QtTest
import qs.modules.common.functions
import "modules/common/functions/levendist.js" as LevendistJs

/**
 * Tests for the Levenshtein distance and the scoring helpers built on it.
 *
 * The scores are used to tell a close spelling of a name from an unrelated
 * one, so the distance of the known cases and the clamping of the scores
 * into the 0..1 range matter.
 */
TestCase {
    id: testCase
    name: "Levenshtein"
    when: true

    function test_the_distance_of_two_identical_strings_is_zero() {
        compare(LevendistJs.levenshteinDistance("abc", "abc"), 0);
        compare(LevendistJs.levenshteinDistance("", ""), 0);
    }

    function test_the_distance_of_two_strings_with_one_different_character_is_one() {
        compare(LevendistJs.levenshteinDistance("abc", "axc"), 1);
        compare(LevendistJs.levenshteinDistance("abc", "abd"), 1);
    }

    function test_the_distance_of_an_empty_string_is_the_length_of_the_other_one() {
        compare(LevendistJs.levenshteinDistance("", "abc"), 3);
        compare(LevendistJs.levenshteinDistance("abc", ""), 3);
    }

    function test_the_distance_counts_insertions_and_deletions() {
        compare(LevendistJs.levenshteinDistance("abc", "abcd"), 1);
        compare(LevendistJs.levenshteinDistance("kitten", "sitting"), 3);
    }

    function test_the_distance_of_two_strings_does_not_depend_on_the_order() {
        compare(
            LevendistJs.levenshteinDistance("kitten", "sitting"),
            LevendistJs.levenshteinDistance("sitting", "kitten"));
    }

    function test_the_score_of_two_identical_strings_is_one() {
        compare(Levendist.computeScore("abc", "abc"), 1);
        compare(Levendist.computeTextMatchScore("abc", "abc"), 1);
    }

    function test_the_score_of_two_unrelated_strings_is_zero() {
        // The score is clamped into the 0..1 range, so unrelated words end
        // up at the lower bound.
        compare(Levendist.computeScore("abc", "xyz"), 0);
        compare(Levendist.computeTextMatchScore("abc", "xyz"), 0);
    }

    function test_the_score_of_a_close_spelling_is_between_zero_and_one() {
        const score = Levendist.computeScore("abc", "abd");
        verify(score > 0);
        verify(score < 1);
        fuzzyCompare(score, 0.7066666666666668, 0.0001);
    }

    function test_the_score_of_an_empty_string_against_an_empty_one_is_one() {
        compare(Levendist.computeScore("", ""), 1);
        compare(Levendist.computeTextMatchScore("", ""), 1);
    }

    function test_the_score_of_a_string_that_contains_the_other_is_one() {
        // The text match score gives the full score when one string is
        // contained in the other.
        compare(Levendist.computeTextMatchScore("abc", "ab"), 1);
        compare(Levendist.computeTextMatchScore("notifications", "notification"), 1);
    }

    function test_the_wrapper_gives_the_same_score_as_the_javascript() {
        fuzzyCompare(
            Levendist.computeScore("kitten", "sitting"),
            LevendistJs.computeScore("kitten", "sitting"), 0.0001);
        fuzzyCompare(
            Levendist.computeTextMatchScore("kitten", "sitting"),
            LevendistJs.computeTextMatchScore("kitten", "sitting"), 0.0001);
    }
}
