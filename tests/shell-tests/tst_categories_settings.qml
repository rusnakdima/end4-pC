import QtQuick
import QtTest
import qs
import qs.modules.common

/**
 * The categories style uses a category rail, a page list and one lazy page
 * Loader. On narrow windows the page list is replaced by a back button and
 * a breadcrumb, like Windows Settings.
 */
TestCase {
    id: testCase
    name: "CategoriesSettings"
    when: true

    property var savedStyle: ""
    property var savedTarget: null
    property var savedPageInstance: null
    property var savedSettingsOpen: false
    property var content: null

    function init() {
        testCase.savedStyle = Config.options.settings.style;
        testCase.savedTarget = GlobalStates.settingsTarget;
        testCase.savedPageInstance = GlobalStates.currentPageInstance;
        testCase.savedSettingsOpen = GlobalStates.settingsOpen;
        Config.options.settings.style = "categories";
        const component = Qt.createComponent("modules/ii/settings/CategoriesSettingsContent.qml");
        compare(component.status, Component.Ready, "CategoriesSettingsContent failed to load: " + component.errorString());
        testCase.content = component.createObject(null, { width: 900, height: 600 });
        verify(testCase.content !== null, "CategoriesSettingsContent could not be created");
    }

    function cleanup() {
        if (testCase.content !== null) testCase.content.destroy();
        Config.options.settings.style = testCase.savedStyle;
        GlobalStates.settingsTarget = testCase.savedTarget;
        GlobalStates.currentPageInstance = testCase.savedPageInstance;
        GlobalStates.settingsOpen = testCase.savedSettingsOpen;
    }

    function test_category_rail_has_five_entries() {
        compare(testCase.content.categoryRepeater.count, 5);
        const labels = [];
        for (let i = 0; i < testCase.content.categoryRepeater.count; i++)
            labels.push(testCase.content.categoryRepeater.itemAt(i).buttonText);
        compare(labels.join(" | "), "Network & internet | Connected devices | Personalization | System | About");
    }

    function test_nav_items_are_packed_from_top_without_gaps() {
        const rail = testCase.content.categoryRepeater;
        verify(rail.itemAt(0).y < 80, "category items must start at the top");
        for (let i = 1; i < rail.count; i++) {
            const previous = rail.itemAt(i - 1);
            const current = rail.itemAt(i);
            verify(current.y - (previous.y + previous.height) <= 12,
                "category items must not be spread over the full height");
        }
        const pages = testCase.content.pageRepeater;
        verify(pages.itemAt(0).y < 80, "page items must start at the top");
        for (let i = 1; i < pages.count; i++) {
            const previous = pages.itemAt(i - 1);
            const current = pages.itemAt(i);
            verify(current.y - (previous.y + previous.height) <= 12,
                "page items must not be spread over the full height");
        }
    }

    function test_category_rail_has_a_search_field() {
        const field = testCase.content.searchFieldItem;
        verify(field !== null && field.visible, "the categories style needs a search field");
    }

    function test_wide_layout_opens_the_first_page_of_the_selected_category() {
        compare(testCase.content.selectedCategory, "Network & internet");
        compare(testCase.content.selectedPageId, "wifi",
            "a wide window must not leave the content pane blank");
        verify(testCase.content.contentLoader.active, "the first page must be loaded");
        testCase.content.selectCategory("Connected devices");
        compare(testCase.content.selectedPageId, "bluetooth");
    }

    function test_network_category_lists_and_loads_wifi() {
        testCase.content.selectCategory("Network & internet");
        compare(testCase.content.pageRepeater.count, 1);
        compare(testCase.content.pageRepeater.itemAt(0).buttonText, "Wi-Fi");
        testCase.content.openPage("wifi");
        tryVerify(() => testCase.content.contentLoader.item !== null, 3000);
        verify(testCase.content.contentLoader.item !== null, "Wi-Fi page did not load");
        compare(testCase.content.selectedPageId, "wifi");
        compare(GlobalStates.currentPageInstance, testCase.content.contentLoader.item);
    }

    function test_narrow_layout_shows_back_and_breadcrumb() {
        testCase.content.width = 500;
        testCase.content.selectCategory("Network & internet");
        testCase.content.openPage("wifi");
        verify(testCase.content.backButtonItem.visible, "back button should be visible in narrow mode");
        verify(testCase.content.breadcrumbItem.visible, "breadcrumb should be visible in narrow mode");
        verify(!testCase.content.pageListPane.visible, "page list should be hidden while a page is open");
        testCase.content.back();
        verify(testCase.content.pageListPane.visible, "back should return to the page list");
        compare(testCase.content.selectedPageId, "");
        compare(testCase.content.contentLoader.active, false);
    }

    function test_deep_link_selects_the_category_and_page() {
        GlobalStates.settingsTarget = { page: "bluetooth" };
        tryVerify(() => GlobalStates.settingsTarget === null, 3000);
        compare(testCase.content.selectedCategory, "Connected devices");
        compare(testCase.content.selectedPageId, "bluetooth");
    }

    function test_cold_open_deep_link_is_consumed() {
        // Production sets settingsTarget before settingsOpen; the window takes
        // time to create this component, so a Connections-only consumer misses
        // the change. Recreate the component with the target already pending.
        testCase.content.destroy();
        testCase.content = null;
        // destroy() is deferred: let the old component's Connections go away
        // before setting the pending target, or it consumes the change first.
        testCase.wait(20);
        GlobalStates.settingsTarget = { page: "wifi" };
        const component = Qt.createComponent("modules/ii/settings/CategoriesSettingsContent.qml");
        compare(component.status, Component.Ready, "CategoriesSettingsContent failed to load: " + component.errorString());
        testCase.content = component.createObject(null, { width: 900, height: 600 });
        verify(testCase.content !== null, "CategoriesSettingsContent could not be created");
        compare(testCase.content.selectedPageId, "wifi");
        compare(testCase.content.selectedCategory, "Network & internet");
        compare(GlobalStates.settingsTarget, null);
    }

    function test_only_one_content_loader_is_active() {
        testCase.content.selectCategory("Network & internet");
        testCase.content.openPage("wifi");
        compare(testCase.content.activeLoaderCount, 1);
        testCase.content.back();
        compare(testCase.content.activeLoaderCount, 0);
    }

    function test_search_breadcrumb_shows_category_path() {
        const component = Qt.createComponent("modules/ii/settings/SettingsSearchPane.qml");
        compare(component.status, Component.Ready, "SettingsSearchPane failed to load: " + component.errorString());
        const pane = component.createObject(null);
        verify(pane !== null, "SettingsSearchPane could not be created");
        pane.query = "keyboard";
        pane.runSearch();
        const result = pane.results.find(r => r.pageId === "keyboard" && r.kind === "page");
        verify(result !== undefined, "keyboard page search result is missing");
        compare(pane.breadcrumbOf(result), "System › Keyboard");
        verify(pane.accept(result), "accepting the keyboard result failed");
        // The already-open content consumes and clears settingsTarget, so
        // assert the resulting page selection instead of the transient target.
        tryVerify(() => testCase.content.selectedPageId === "keyboard", 3000);
        compare(testCase.content.selectedCategory, "System");
        pane.destroy();
    }
}
