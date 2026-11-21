import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.widgets

/**
 * Geometry of the shared selection highlight in the settings navigation rail.
 *
 * The icon is square, so in collapsed (icon-only) mode the selection indicator
 * must be a circle: equal width and height, centred on the icon. A wide+short
 * pill reads as an ellipse behind a square icon.
 */
TestCase {
    id: testCase
    name: "NavigationRail"
    when: true

    property string sandboxPath: "/tmp/end4-pc-shell-test-nav-rail-config.json"
    property string originalPath: ""
    property var rail: null

    Component {
        id: railComponent
        NavigationRailTabArray {
            width: 56
            height: 220
            currentIndex: 1
            Repeater {
                model: 3
                NavigationRailButton {
                    required property int index
                    toggled: index === 1
                    buttonIcon: "settings"
                    buttonText: "Page " + index
                }
            }
        }
    }

    function selectionHighlight() {
        return testCase.rail.selectionHighlight;
    }

    function createRail() {
        testCase.rail = railComponent.createObject(null);
        verify(testCase.rail !== null, "the rail failed to create");
        return selectionHighlight();
    }

    function init() {
        testCase.rail = null;
        testCase.originalPath = Config.filePath;
        if (Config.filePath !== testCase.sandboxPath)
            Config.filePath = testCase.sandboxPath;
        for (let i = 0; i < 100 && !Config.ready; ++i) wait(100);
    }

    function cleanup() {
        if (testCase.rail !== null) {
            testCase.rail.destroy();
            testCase.rail = null;
        }
        if (Config.filePath === testCase.sandboxPath)
            Config.filePath = testCase.originalPath;
    }

    function test_compact_highlight_is_a_circle_centred_on_the_icon() {
        Config.options.settings.sidebarDensity = "compact";
        const highlight = createRail();
        verify(highlight !== null, "the selection highlight was not created");

        // Square icon -> round indicator: width must equal height (26).
        compare(Math.round(highlight.width), 26);
        compare(Math.round(highlight.height), 26);
        // Centred in the 56px-wide collapsed rail: (56 - 26) / 2.
        compare(Math.round(highlight.x), 15);
        // Tab 1 is 44px tall, its 26px circle is centred: 44 + (44 - 26) / 2.
        compare(Math.round(highlight.y), 53);
    }

    function test_default_collapsed_highlight_is_a_circle_centred_on_the_icon() {
        Config.options.settings.sidebarDensity = "default";
        const highlight = createRail();
        verify(highlight !== null, "the selection highlight was not created");

        compare(Math.round(highlight.width), 32);
        compare(Math.round(highlight.height), 32);
        // Centred in the 56px-wide collapsed rail: (56 - 32) / 2.
        compare(Math.round(highlight.x), 12);
        compare(Math.round(highlight.y), 56 + (56 - 32) / 2);
    }

    function test_expanded_highlight_uses_the_button_visual_width() {
        Config.options.settings.sidebarDensity = "default";
        testCase.rail = railComponent.createObject(null);
        verify(testCase.rail !== null, "the rail failed to create");
        testCase.rail.expanded = true;
        testCase.rail.currentIndex = 1;

        const highlight = selectionHighlight();
        verify(highlight !== null, "the selection highlight was not created");
        const content = testCase.rail.children[0].contentItem.children;
        const column = content.find(child => child.children.some(kid => kid.baseSize !== undefined));
        const button = column?.children.find(child => child.baseSize !== undefined);

        verify(button !== null && button !== undefined, "the first tab button was not found");
        compare(Math.round(highlight.width), Math.round(button.visualWidth));
        compare(Math.round(highlight.height), Math.round(button.baseSize));
    }
}
