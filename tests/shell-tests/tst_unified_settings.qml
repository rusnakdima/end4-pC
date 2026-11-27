import QtQuick
import QtTest
import qs
import qs.modules.common

TestCase {
    id: testCase
    name: "UnifiedSettings"
    when: true

    property var savedStyle: ""
    property var savedTarget: null
    property var savedPageInstance: null
    property var content: null

    function makeContent(width) {
        const component = Qt.createComponent("modules/ii/settings/UnifiedSettingsContent.qml");
        compare(component.status, Component.Ready, "UnifiedSettingsContent failed to load: " + component.errorString());
        const item = component.createObject(null, { width: width, height: 600 });
        verify(item !== null, "UnifiedSettingsContent could not be created");
        return item;
    }

    function init() {
        testCase.savedStyle = Config.options.settings.style;
        testCase.savedTarget = GlobalStates.settingsTarget;
        testCase.savedPageInstance = GlobalStates.currentPageInstance;
        Config.options.settings.style = "default";
        testCase.content = testCase.makeContent(1200);
    }

    function cleanup() {
        if (testCase.content !== null) testCase.content.destroy();
        Config.options.settings.style = testCase.savedStyle;
        GlobalStates.settingsTarget = testCase.savedTarget;
        GlobalStates.currentPageInstance = testCase.savedPageInstance;
    }

    function test_toolbar_has_visible_search_and_both_panel_toggles() {
        verify(testCase.content.searchFieldItem.visible, "search field must be visible in every layout");
        verify(testCase.content.categoryListPaneItem.visible, "category panel starts visible");
        verify(testCase.content.pageListPane.visible, "page list starts visible");
        testCase.content.toggleCategoryPanel();
        verify(!testCase.content.categoryListPaneItem.visible, "category panel must collapse");
        testCase.content.toggleCategoryPanel();
        verify(testCase.content.categoryListPaneItem.visible, "category panel must expand again");
        testCase.content.togglePageListPanel();
        verify(!testCase.content.pageListPane.visible, "page list must collapse");
    }

    function test_content_pane_is_never_clipped_when_width_shrinks() {
        for (const width of [1200, 900, 700, 520]) {
            testCase.content.width = width;
            wait(50);
            const pane = testCase.content.contentPaneItem;
            verify(pane.width > 0, "content pane must have width at " + width);
            verify(pane.x + pane.width <= width + 1, "content pane x=" + pane.x + " w=" + pane.width + " at " + width);
            verify(pane.width >= testCase.content.minimumContentWidth - 1,
                "width=" + width + " root=" + testCase.content.width + " pane=" + pane.width +
                " autoPage=" + testCase.content.autoPageListCollapsed + " autoCat=" + testCase.content.autoCategoryCollapsed +
                " listVis=" + testCase.content.pageListPane.visible + " listW=" + testCase.content.pageListPane.width +
                " catW=" + testCase.content.categoryListPaneItem.width);
        }
    }

    function test_auto_collapse_restores_user_choice_when_widened() {
        testCase.content.width = 520;
        verify(!testCase.content.categoryListPaneItem.visible, "narrow width auto-collapses the rail");
        testCase.content.width = 1200;
        verify(testCase.content.categoryListPaneItem.visible, "widening restores the user's choice");
    }

    function test_narrow_mode_uses_back_and_breadcrumb() {
        testCase.content.width = 520;
        testCase.content.openPage("wifi");
        verify(testCase.content.backButtonItem.visible, "narrow mode needs a back button");
        verify(testCase.content.breadcrumbItem.visible, "narrow mode needs a breadcrumb");
        testCase.content.back();
        compare(testCase.content.selectedPageId, "");
        testCase.content.width = 1200;
        wait(50);
        verify(testCase.content.pageListPane.visible, "back returns to the page list");
    }

    function test_live_style_change_reapplies_preset() {
        Config.options.settings.style = "minimal";
        tryCompare(testCase.content, "categoryIconsOnly", true, 1000);
        Config.options.settings.style = "default";
        tryCompare(testCase.content, "categoryIconsOnly", false, 1000);
    }

    function test_compatibility_surface_for_tab_handling() {
        verify(testCase.content.pages.length >= 20, "the flat page model must be available");
        verify(testCase.content.currentPage >= 0 && testCase.content.currentPage < testCase.content.pages.length);
        verify(testCase.content.showingProfile === false);
    }

    function test_narrow_page_open_hides_all_side_panes() {
        testCase.content.width = 520;
        testCase.content.openPage("wifi");
        wait(100);
        verify(!testCase.content.categoryListPaneItem.visible, "category rail must hide when a page is open on a narrow window");
        verify(!testCase.content.pageListPane.visible, "page list must hide when a page is open on a narrow window");
        testCase.content.back();
        wait(50);
        // Very narrow windows keep all side panes hidden, KDE-style.
        verify(!testCase.content.categoryListPaneItem.visible, "category rail stays hidden at very narrow width");
        verify(!testCase.content.pageListPane.visible, "page list stays hidden at very narrow width");
        testCase.content.width = 900;
        wait(50);
        verify(testCase.content.categoryListPaneItem.visible, "widening restores the category rail");
        verify(testCase.content.pageListPane.visible, "widening restores the page list");
    }

    function test_loaded_page_compresses_to_the_content_pane() {
        testCase.content.width = 520;
        testCase.content.openPage("wifi");
        const pane = testCase.content.contentPaneItem;
        tryVerify(() => testCase.content.contentLoader.item !== null, 2000);
        wait(100);
        const page = testCase.content.contentLoader.item;
        verify(page.baseWidth <= pane.width - 20,
            "baseWidth=" + page.baseWidth + " paneWidth=" + pane.width +
            " loaderWidth=" + testCase.content.contentLoader.width);
    }

    function test_side_panes_are_opaque() {
        compare(testCase.content.categoryListPaneItem.color.a, 1, "category rail must not let content show through");
        compare(testCase.content.pageListPane.color.a, 1, "page list must not let content show through");
    }

    function test_content_pane_is_opaque_and_themed() {
        const pane = testCase.content.contentPaneItem;
        compare(pane.color.a, 1, "content pane must not let the desktop show through");
        compare(String(pane.color), String(Appearance.colors.colLayer0Base), "content pane must use a themed opaque surface");
    }
}
