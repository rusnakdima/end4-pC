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
    property var content: null

    function init() {
        testCase.savedStyle = Config.options.settings.style;
        testCase.savedTarget = GlobalStates.settingsTarget;
        testCase.savedPageInstance = GlobalStates.currentPageInstance;
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
    }

    function test_category_rail_has_five_entries() {
        compare(testCase.content.categoryRepeater.count, 5);
        const labels = [];
        for (let i = 0; i < testCase.content.categoryRepeater.count; i++)
            labels.push(testCase.content.categoryRepeater.itemAt(i).buttonText);
        compare(labels.join(" | "), "Network & internet | Connected devices | Personalization | System | About");
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

    function test_only_one_content_loader_is_active() {
        testCase.content.selectCategory("Network & internet");
        testCase.content.openPage("wifi");
        compare(testCase.content.activeLoaderCount, 1);
        testCase.content.back();
        compare(testCase.content.activeLoaderCount, 0);
    }
}
