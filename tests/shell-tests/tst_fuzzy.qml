import QtQuick
import QtTest
import qs.modules.common.functions
import "modules/common/functions/fuzzysort.js" as FuzzySort

/**
 * Tests for the fuzzy search.
 *
 * The search is used by the launcher and by the settings search, so a query
 * that matches has to find the entry, a query that matches nothing has to
 * find nothing at all and the better match has to come first.
 */
TestCase {
    id: testCase
    name: "Fuzzy"
    when: true

    function targets(results) {
        const out = [];
        for (let i = 0; i < results.length; ++i) out.push(results[i].target);
        return out;
    }

    function test_a_query_that_matches_finds_the_entry() {
        const results = Fuzzy.go("abc", ["abc", "xyz"]);
        verify(results.length > 0);
        verify(targets(results).indexOf("abc") !== -1);
    }

    function test_a_query_that_matches_nothing_finds_nothing() {
        const results = Fuzzy.go("zzz", ["abc", "xyz"]);
        compare(results.length, 0);
    }

    function test_an_empty_query_finds_nothing() {
        // The search returns no results for an empty query, it does not
        // return every target.
        const results = Fuzzy.go("", ["abc", "xyz"]);
        compare(results.length, 0);
    }

    function test_a_query_against_an_empty_list_finds_nothing() {
        const results = Fuzzy.go("abc", []);
        compare(results.length, 0);
    }

    function test_the_better_match_comes_first() {
        // "ab" is the start of "ab", so it scores better than "xxab".
        const results = Fuzzy.go("ab", ["xxab", "ab"]);
        verify(results.length === 2);
        compare(results[0].target, "ab");
        compare(results[1].target, "xxab");
    }

    function test_the_score_of_the_better_match_is_higher() {
        const results = Fuzzy.go("ab", ["xxab", "ab"]);
        verify(results[0].score > results[1].score);
    }

    function test_the_matched_characters_are_reported() {
        const results = Fuzzy.go("ab", ["abc"]);
        verify(results.length === 1);
        compare(results[0].indexes.join(","), "0,1");
    }

    function test_a_search_over_objects_uses_the_key() {
        const items = [{ name: "alpha" }, { name: "beta" }];
        const results = Fuzzy.go("alp", items, { key: "name" });
        verify(results.length === 1);
        compare(results[0].obj.name, "alpha");
    }

    function test_the_wrapper_delegates_to_the_search() {
        const results = FuzzySort.go("abc", ["abc"]);
        verify(results.length === 1);
        compare(results[0].target, "abc");
    }
}
