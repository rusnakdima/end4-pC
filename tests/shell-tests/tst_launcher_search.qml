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
}
