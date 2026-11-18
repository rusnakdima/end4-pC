import QtQuick
import QtTest
import qs.modules.common.functions

/**
 * Windows-style projection is pure layout math, so the four modes are tested
 * without a compositor: the descriptors below mirror what hyprctl reports.
 */
TestCase {
    id: testCase
    name: "Projection"
    when: true

    function monitorFixture() {
        return [
            {
                name: "eDP-1", description: "Built-in Display",
                width: 1920, height: 1080, currentMode: "1920x1080@60.00Hz",
                availableModes: ["1920x1080@60.00Hz"],
                x: 0, y: 0, scale: 1, transform: 0
            },
            {
                name: "HDMI-A-1", description: "LG TV",
                width: 2560, height: 1440, currentMode: "2560x1440@60.00Hz",
                availableModes: ["2560x1440@60.00Hz", "1920x1080@60.00Hz"],
                x: 1920, y: 0, scale: 1, transform: 0
            }
        ]
    }

    function test_internal_panel_detection() {
        verify(ProjectionUtils.isInternal({ name: "eDP-1", description: "Panel" }));
        verify(ProjectionUtils.isInternal({ name: "LVDS-1", description: "LCD" }));
        verify(ProjectionUtils.isInternal({ name: "DP-1", description: "Built-in eDP panel" }));
        verify(!ProjectionUtils.isInternal({ name: "HDMI-A-1", description: "LG TV" }));
        verify(!ProjectionUtils.isInternal(null));
    }

    function test_mode_parsing_and_rotation() {
        const parsed = ProjectionUtils.parseMode("2560x1440@119.98Hz");
        compare(parsed.width, 2560);
        compare(parsed.height, 1440);
        compare(parsed.hz, 119.98);
        compare(ProjectionUtils.parseMode("nonsense"), null);

        const rotated = { width: 1920, height: 1080, transform: 1, scale: 1 };
        compare(ProjectionUtils.logicalWidth(rotated), 1080);
        compare(ProjectionUtils.logicalHeight(rotated), 1920);
        compare(ProjectionUtils.layoutWidth(rotated), 1080);
    }

    function test_pc_screen_only_disables_the_external() {
        const patches = ProjectionUtils.project(monitorFixture(), "pc", "right");
        compare(patches.length, 2);
        compare(patches[0].name, "eDP-1");
        verify(!patches[0].changes.disabled);
        compare(patches[1].name, "HDMI-A-1");
        verify(patches[1].changes.disabled);
    }

    function test_duplicate_mirrors_the_internal_panel() {
        const patches = ProjectionUtils.project(monitorFixture(), "duplicate", "right");
        compare(patches[1].changes.mirror, "eDP-1");
        // Only a mode the target actually advertises is picked.
        compare(patches[1].changes.currentMode, "1920x1080@60.00Hz");
    }

    function test_duplicate_falls_back_to_the_target_mode() {
        const monitors = monitorFixture();
        monitors[1].availableModes = ["2560x1440@60.00Hz"];
        const patches = ProjectionUtils.project(monitors, "duplicate", "right");
        compare(patches[1].changes.currentMode, "2560x1440@60.00Hz");
    }

    function test_extend_places_the_external_next_to_the_internal() {
        const right = ProjectionUtils.project(monitorFixture(), "extend", "right");
        compare(right[1].changes.x, 1920);
        compare(right[1].changes.y, 0);
        compare(right[1].changes.mirror, "");
        verify(!right[1].changes.disabled);

        const left = ProjectionUtils.project(monitorFixture(), "extend", "left");
        compare(left[1].changes.x, -2560);
        compare(left[1].changes.y, 0);

        const below = ProjectionUtils.project(monitorFixture(), "extend", "below");
        compare(below[1].changes.x, 0);
        compare(below[1].changes.y, 1080);
    }

    function test_second_screen_only_disables_internal_and_uses_origin() {
        const patches = ProjectionUtils.project(monitorFixture(), "second", "right");
        verify(patches[0].changes.disabled);
        verify(!patches[1].changes.disabled);
        compare(patches[1].changes.x, 0);
        compare(patches[1].changes.y, 0);
    }

    function test_full_changes_restore_the_saved_layout() {
        const monitors = monitorFixture();
        monitors[1].baseX = 400;
        monitors[1].baseY = -100;
        monitors[1].baseScale = 2;
        monitors[1].baseTransform = 3;
        const changes = ProjectionUtils.fullChanges(monitors[1]);
        compare(changes.x, 400);
        compare(changes.y, -100);
        compare(changes.scale, 2);
        compare(changes.transform, 3);
    }

    function test_three_monitors_chain_without_overlap() {
        const monitors = monitorFixture();
        monitors.push({
            name: "DP-2", description: "Second TV",
            width: 1920, height: 1080, currentMode: "1920x1080@60.00Hz",
            availableModes: ["1920x1080@60.00Hz"],
            x: 4480, y: 0, scale: 1, transform: 0
        });
        const patches = ProjectionUtils.project(monitors, "extend", "right");
        compare(patches.length, 3);
        compare(patches[1].changes.x, 1920);
        compare(patches[2].changes.x, 4480);
    }
}
