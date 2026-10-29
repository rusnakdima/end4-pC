import QtQuick
import QtTest
import qs.modules.common
import qs.modules.ii.bar as Bar

/**
 * Tests for the bar content.
 *
 * The bar resolves the widget names of the layout into the widget files of
 * the bar, decides which of them may be mirrored and which of them get a
 * material pill behind them. Those rules only depend on the name of the
 * widget and on the style of the bar, so they can be checked without a
 * compositor.
 */
TestCase {
    id: testCase
    name: "BarContent"
    when: true

    // The bar is an item that lives in a window, so it is created below a
    // host item.
    Component {
        id: hostFactory
        Item { width: 1200; height: 40 }
    }

    Component {
        id: barFactory
        Bar.BarContent {}
    }

    property var barInstance: null
    property var hostInstance: null

    function init() {
        testCase.hostInstance = hostFactory.createObject(null);
        testCase.barInstance = barFactory.createObject(testCase.hostInstance);
        verify(testCase.barInstance !== null);
    }

    function cleanup() {
        if (testCase.barInstance !== null) {
            testCase.barInstance.destroy();
            testCase.barInstance = null;
        }
        if (testCase.hostInstance !== null) {
            testCase.hostInstance.destroy();
            testCase.hostInstance = null;
        }
    }

    function test_a_widget_name_is_resolved_to_its_widget_file() {
        const bar = testCase.barInstance;

        verify(String(bar.getWidgetUrl("clockWidget")).endsWith("/ClockWidget.qml"));
        verify(String(bar.getWidgetUrl("sysTray")).endsWith("/SysTray.qml"));
        verify(String(bar.getWidgetUrl("activeWindow")).endsWith("/ActiveWindow.qml"));
    }

    function test_a_widget_without_a_name_has_no_file() {
        compare(testCase.barInstance.getWidgetUrl(""), "");
        compare(testCase.barInstance.getWidgetUrl(null), "");
    }

    function test_only_the_visualizer_may_be_mirrored() {
        const bar = testCase.barInstance;

        compare(bar.canMirror("visualizer"), true);
        compare(bar.canMirror("clockWidget"), false);
        compare(bar.canMirror("media"), false);
        compare(bar.canMirror(""), false);
    }

    function test_the_visualizer_is_mirrored_after_an_odd_number_of_visualizers() {
        const bar = testCase.barInstance;

        compare(bar.getMirroredForIndex(["visualizer"], 0), false);
        compare(bar.getMirroredForIndex(["visualizer", "visualizer"], 1), true);
        compare(bar.getMirroredForIndex(["visualizer", "visualizer", "visualizer"], 2), false);
        compare(bar.getMirroredForIndex(["visualizer", "visualizer", "visualizer"], 1), true);
    }

    function test_a_visualizer_behind_another_widget_is_not_mirrored() {
        const bar = testCase.barInstance;

        compare(bar.getMirroredForIndex(["clockWidget", "visualizer"], 1), false);
        compare(bar.getMirroredForIndex([], 0), false);
    }

    function test_the_blacklisted_widgets_never_get_a_material_pill() {
        const bar = testCase.barInstance;

        compare(bar.shouldPaintMaterialPill("workspaces"), false);
        compare(bar.shouldPaintMaterialPill("divisor"), false);
        compare(bar.shouldPaintMaterialPill("powerButton"), false);
        compare(bar.shouldPaintMaterialPill("docktoPanel"), false);
        compare(bar.shouldPaintMaterialPill("leftSidebarButton"), false);
        compare(bar.shouldPaintMaterialPill("activeWindow"), false);
        compare(bar.shouldPaintMaterialPill("avatar"), false);
    }

    function test_a_material_pill_is_painted_only_in_the_material_styles() {
        const bar = testCase.barInstance;

        compare(bar.shouldPaintMaterialPill("media"), bar.isMaterial);
        compare(bar.shouldPaintMaterialPill("resources"), bar.isMaterial);
        compare(bar.shouldPaintMaterialPill("clockWidget"), bar.isMaterial);
    }

    function test_the_pill_colour_follows_the_widget() {
        const bar = testCase.barInstance;

        if (bar.isMaterial) {
            compare(String(bar.getMaterialPillColor("media")), String(Appearance.colors.colSecondaryContainer));
            compare(String(bar.getMaterialPillColor("sysTray")), String(Appearance.colors.colSecondaryContainer));
            compare(String(bar.getMaterialPillColor("resources")), String(Appearance.colors.colTertiaryContainer));
            compare(String(bar.getMaterialPillColor("systemIcons")), String(Appearance.colors.colPrimary));
            compare(String(bar.getMaterialPillColor("clockWidget")), String(Appearance.colors.colPrimaryContainer));
        } else {
            compare(String(bar.getMaterialPillColor("media")), String(Appearance.colors.colPrimaryContainer));
            compare(String(bar.getMaterialPillColor("resources")), String(Appearance.colors.colPrimaryContainer));
            compare(String(bar.getMaterialPillColor("systemIcons")), String(Appearance.colors.colPrimaryContainer));
        }
    }

    function test_the_tray_widget_is_dropped_when_the_tray_is_empty() {
        const bar = testCase.barInstance;

        const layout = ["sysTray", "clockWidget"];
        const filtered = bar.filterLayout(layout);

        // The clock is always kept, the tray only when the live tray has
        // something in it.
        compare(filtered.includes("clockWidget"), true);
        compare(filtered.includes("sysTray"), bar.trayHasItems);
    }

    function test_the_layout_is_not_changed_by_the_filter() {
        const bar = testCase.barInstance;

        const layout = ["sysTray", "clockWidget"];
        bar.filterLayout(layout);

        compare(layout.length, 2);
    }
}
