import QtQuick
import QtTest
import qs.services

TestCase {
    id: testCase
    name: "LauncherSearch"
    when: true

    function test_result_query_is_debounced() {
        LauncherSearch.query = "";
        tryCompare(LauncherSearch, "resultQuery", "");
        LauncherSearch.query = "r";
        compare(LauncherSearch.resultQuery, "");
        tryCompare(LauncherSearch, "resultQuery", "r", 1000);
    }

    function test_results_are_capped() {
        LauncherSearch.query = "a";
        tryCompare(LauncherSearch, "resultQuery", "a", 1000);
        verify(LauncherSearch.results.length <= LauncherSearch.resultsLimit);
    }

    function test_result_object_creation_is_capped() {
        LauncherSearch.query = "";
        tryCompare(LauncherSearch, "resultQuery", "", 1000);
        LauncherSearch.query = "a";
        tryCompare(LauncherSearch, "resultQuery", "a", 1000);
        verify(LauncherSearch.resultStats.objectsCreated <= LauncherSearch.resultsLimit,
            "created " + LauncherSearch.resultStats.objectsCreated + " result objects");
    }

    function test_double_change_within_debounce_computes_once() {
        LauncherSearch.query = "";
        tryCompare(LauncherSearch, "resultQuery", "", 1000);
        // Let the debounce timer for the empty query finish before counting.
        wait(300);
        LauncherSearch.resultStats.computations = 0;
        LauncherSearch.query = "r";
        LauncherSearch.query = "re";
        tryCompare(LauncherSearch, "resultQuery", "re", 1000);
        compare(LauncherSearch.resultStats.computations, 1);
    }

    function test_math_result_change_does_not_recompute_results() {
        LauncherSearch.query = "";
        tryCompare(LauncherSearch, "resultQuery", "", 1000);
        // Let the pending math calculation finish before counting.
        wait(300);
        LauncherSearch.resultStats.computations = 0;
        LauncherSearch.mathResult = "42";
        wait(300);
        // A mathResult update must not be counted as a new query search.
        compare(LauncherSearch.resultStats.computations, 0);
    }
}
