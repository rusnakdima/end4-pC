import QtQuick
import QtTest
import "modules/common/functions/SettingsTabDecision.js" as TabDecision

/**
 * Tab in Settings cycles pages only when the active content exposes pages.
 * The categories content has no page list, so Tab must stay available for
 * native focus navigation instead of being swallowed.
 */
TestCase {
    id: testCase
    name: "SettingsTab"
    when: true

    function test_tab_without_pages_is_not_consumed() {
        const decision = TabDecision.decide([], 0, "forward");
        verify(decision !== null, "decide() must return a decision");
        verify(!decision.accept, "Tab without pages must not be consumed");
    }

    function test_backtab_without_pages_is_not_consumed() {
        const decision = TabDecision.decide(undefined, 0, "back");
        verify(!decision.accept, "Backtab without pages must not be consumed");
    }

    function test_tab_cycles_forward_and_wraps() {
        const pages = ["appearance", "bar", "about"];
        compare(TabDecision.decide(pages, 0, "forward").currentPage, 1);
        compare(TabDecision.decide(pages, 2, "forward").currentPage, 0);
    }

    function test_backtab_cycles_backward_and_wraps() {
        const pages = ["appearance", "bar", "about"];
        compare(TabDecision.decide(pages, 0, "back").currentPage, 2);
        compare(TabDecision.decide(pages, 1, "back").currentPage, 0);
    }
}
