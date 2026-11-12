import QtQuick
import QtTest
import "QuickToggles.js" as QuickToggles

/**
 * Tests for the quick toggle grid geometry.
 *
 * The panel uses these numbers to lay tiles into rows, to move the drop
 * indicator, and — while a tile is dragged — to slide the other tiles
 * aside so a gap opens where the tile will land. If the arithmetic is
 * wrong the tiles jump when the drag ends, so the packing, the slot
 * rectangles, the insertion choice and the glide offsets are all pinned
 * down here.
 */
TestCase {
    id: testCase
    name: "QuickToggles"
    when: windowShown

    // 5 columns, 100px cells, 6px spacing: a tile of size n is
    // 100n + 6(n-1) wide, and a full row is 5 cells + 4 gaps = 524px.
    readonly property int cols: 5
    readonly property real cell: 100
    readonly property real gap: 6
    readonly property real tileH: 56

    function t(type, size) {
        return { type: type, size: size };
    }

    // --- packRows -----------------------------------------------------

    function test_pack_fills_rows_left_to_right() {
        const rows = QuickToggles.packRows([
            t("a", 2), t("b", 2), t("c", 1), t("d", 3)
        ], cols);
        compare(rows.length, 2);
        compare(rows[0].map(x => x.type), ["a", "b", "c"]); // 2+2+1 = 5
        compare(rows[1].map(x => x.type), ["d"]);           // 3 fits alone
    }

    function test_pack_starts_new_row_when_full() {
        const rows = QuickToggles.packRows([
            t("a", 3), t("b", 3), t("c", 3)
        ], cols);
        compare(rows.length, 3);
        compare(rows[1].map(x => x.type), ["b"]);
        compare(rows[2].map(x => x.type), ["c"]);
    }

    function test_pack_skips_null_entries() {
        const rows = QuickToggles.packRows([null, t("a", 2), null, t("b", 3)], cols);
        compare(rows.length, 1);
        compare(rows[0].map(x => x.type), ["a", "b"]);
    }

    function test_pack_leaves_no_empty_rows() {
        // Every row that comes back has at least one tile, so the panel
        // never renders a zero-height row.
        const rows = QuickToggles.packRows([t("a", 5), t("b", 1)], cols);
        for (const row of rows) verify(row.length > 0);
    }

    function test_row_count() {
        compare(QuickToggles.rowCount([], cols), 0);
        compare(QuickToggles.rowCount([t("a", 5)], cols), 1);
        compare(QuickToggles.rowCount([t("a", 3), t("b", 3)], cols), 2);
        compare(QuickToggles.rowCount([t("a", 3), t("b", 2)], cols), 1);
    }

    // --- tileWidth / rowWidth ----------------------------------------

    function test_tile_width_covers_cells_plus_gaps() {
        compare(QuickToggles.tileWidth(1, cell, gap), 100);
        compare(QuickToggles.tileWidth(2, cell, gap), 206);
        compare(QuickToggles.tileWidth(3, cell, gap), 312);
    }

    function test_row_width_is_tiles_plus_gaps_between() {
        // Three size-1 tiles: 300px of cells + 2 gaps of 6 = 312.
        compare(QuickToggles.rowWidth([t("a", 1), t("b", 1), t("c", 1)], cell, gap), 312);
        compare(QuickToggles.rowWidth([], cell, gap), 0);
        compare(QuickToggles.rowWidth(null, cell, gap), 0);
    }

    // --- slotRects ----------------------------------------------------

    function test_slot_rects_place_tiles_across_a_row() {
        const rects = QuickToggles.slotRects(
            [t("a", 2), t("b", 1), t("c", 2)], cols, cell, tileH, gap);
        compare(rects.a, { x: 0, y: 0, w: 206, h: 56 });
        compare(rects.b, { x: 212, y: 0, w: 100, h: 56 });
        compare(rects.c, { x: 318, y: 0, w: 206, h: 56 });
    }

    function test_slot_rects_stack_rows_at_tile_height_plus_gap() {
        const rects = QuickToggles.slotRects(
            [t("a", 3), t("b", 3)], cols, cell, tileH, gap);
        // Row 1 is full (3), b wraps to row 2 at y = 56 + 6.
        compare(rects.a.y, 0);
        compare(rects.b.y, 62);
        compare(rects.b.x, 0);
    }

    function test_slot_rects_keyed_by_type_not_position() {
        const rects = QuickToggles.slotRects(
            [t("mic", 1), t("net", 1)], cols, cell, tileH, gap);
        verify(rects.mic !== undefined);
        verify(rects.net !== undefined);
        compare(rects.net.x, 106);
    }

    // --- insertionIndex / previewOrderOf ------------------------------

    function test_insertion_prefers_the_slot_under_the_pointer() {
        // One row of five size-1 tiles; pointer over the middle tile's
        // centre → the dragged tile lands there.
        const order = [t("a", 1), t("b", 1), t("c", 1), t("d", 1), t("e", 1)];
        // Slot centres: 50, 156, 262, 368, 474.
        const idx = QuickToggles.insertionIndex(order, "x", { x: 262, y: 28 }, cell, tileH, gap, cols);
        // "x" is not in the order at all, so nothing can be dragged out;
        // the function bails rather than guessing.
        compare(idx, -1);
    }

    function test_insertion_index_of_a_held_tile() {
        // a b c d e, holding "c": rest = a b d e. Pointer over d's
        // original slot centre (368) → c takes that slot, which is
        // index 3 in the rest list.
        const order = [t("a", 1), t("b", 1), t("c", 1), t("d", 1), t("e", 1)];
        const idx = QuickToggles.insertionIndex(order, "c", { x: 368, y: 28 }, cell, tileH, gap, cols);
        compare(idx, 3);
    }

    function test_insertion_clamps_to_the_far_edge() {
        // Pointer far past the right edge still yields a valid index.
        const order = [t("a", 1), t("b", 1), t("c", 1)];
        const idx = QuickToggles.insertionIndex(order, "a", { x: 5000, y: 28 }, cell, tileH, gap, cols);
        verify(idx >= 0 && idx <= 2);
        // Dropping to the right of everything puts a last.
        const preview = QuickToggles.previewOrderOf(order, "a", idx);
        compare(preview[preview.length - 1].type, "a");
    }

    function test_insertion_handles_a_wrapped_row() {
        // Six size-1 tiles in 5 columns wrap to two rows; a pointer in
        // row 2 should pick an index that lands the tile down there.
        const order = [t("a", 1), t("b", 1), t("c", 1), t("d", 1), t("e", 1), t("f", 1)];
        const idx = QuickToggles.insertionIndex(order, "f", { x: 50, y: 90 }, cell, tileH, gap, cols);
        const preview = QuickToggles.previewOrderOf(order, "f", idx);
        const rects = QuickToggles.slotRects(preview, cols, cell, tileH, gap);
        compare(rects.f.y, 62);
    }

    function test_preview_order_removes_then_reinserts() {
        const order = [t("a", 1), t("b", 1), t("c", 1)];
        compare(QuickToggles.previewOrderOf(order, "a", 2).map(x => x.type), ["b", "c", "a"]);
        compare(QuickToggles.previewOrderOf(order, "a", 0).map(x => x.type), ["a", "b", "c"]);
        // The dragged tile is not in the order → order is unchanged.
        compare(QuickToggles.previewOrderOf(order, "zz", 1).map(x => x.type), ["a", "b", "c"]);
    }

    // --- shiftsFor ----------------------------------------------------

    function test_shift_is_zero_when_nothing_moves() {
        const order = [t("a", 1), t("b", 1), t("c", 1)];
        const shifts = QuickToggles.shiftsFor(order, order.slice(), "a", cell, tileH, gap, cols);
        compare(shifts.b, { dx: 0, dy: 0 });
        compare(shifts.c, { dx: 0, dy: 0 });
        verify(shifts.a === undefined); // the dragged tile never shifts
    }

    function test_shift_moves_later_tiles_left_into_the_gap() {
        // Holding a and dropping it at index 2: b, c slide left by one
        // slot, a lands at the end.
        const order = [t("a", 1), t("b", 1), t("c", 1)];
        const preview = QuickToggles.previewOrderOf(order, "a", 2);
        const shifts = QuickToggles.shiftsFor(order, preview, "a", cell, tileH, gap, cols);
        compare(preview.map(x => x.type), ["b", "c", "a"]);
        compare(shifts.b, { dx: -106, dy: 0 });
        compare(shifts.c, { dx: -106, dy: 0 });
    }

    function test_shift_opens_a_gap_in_a_wrapped_packing() {
        // 5 columns, six size-1 tiles: row 1 a b c d e, row 2 f.
        // Dragging a to the end makes row 1 b c d e f, so everyone in
        // it slides one slot left and f climbs from row 2 into the gap.
        const order = [t("a", 1), t("b", 1), t("c", 1), t("d", 1), t("e", 1), t("f", 1)];
        const preview = QuickToggles.previewOrderOf(order, "a", 5);
        const shifts = QuickToggles.shiftsFor(order, preview, "a", cell, tileH, gap, cols);
        compare(preview.map(x => x.type), ["b", "c", "d", "e", "f", "a"]);
        compare(shifts.b, { dx: -106, dy: 0 });
        compare(shifts.e, { dx: -106, dy: 0 });
        // f: row 2 slot 1 → row 1 slot 5.
        compare(shifts.f, { dx: 424, dy: -62 });
    }

    function test_shift_accounts_for_different_tile_sizes() {
        // a is size 2 (206px wide), b size 1. Dropping a after b
        // shifts b left by a's full width plus a gap: 212.
        const order = [t("a", 2), t("b", 1)];
        const preview = QuickToggles.previewOrderOf(order, "a", 1);
        const shifts = QuickToggles.shiftsFor(order, preview, "a", cell, tileH, gap, cols);
        compare(preview.map(x => x.type), ["b", "a"]);
        compare(shifts.b, { dx: -212, dy: 0 });
    }
}
