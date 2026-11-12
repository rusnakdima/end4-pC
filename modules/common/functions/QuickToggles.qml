pragma Singleton
import Quickshell
import "QuickToggles.js" as QuickTogglesJs

/**
 * Wrapper for QuickToggles.js to play nicely with Quickshell's imports.
 *
 * The geometry of the quick toggle grid — packing toggles into rows,
 * where each tile sits, and how far tiles glide while one is dragged.
 */

Singleton {
    function packRows(toggles, columns) {
        return QuickTogglesJs.packRows(toggles, columns);
    }

    function tileWidth(size, baseCellWidth, spacing) {
        return QuickTogglesJs.tileWidth(size, baseCellWidth, spacing);
    }

    function rowWidth(row, baseCellWidth, spacing) {
        return QuickTogglesJs.rowWidth(row, baseCellWidth, spacing);
    }

    function slotRects(order, columns, baseCellWidth, baseCellHeight, spacing) {
        return QuickTogglesJs.slotRects(order, columns, baseCellWidth, baseCellHeight, spacing);
    }

    function insertionIndex(order, draggedType, pointer, baseCellWidth, baseCellHeight, spacing, columns) {
        return QuickTogglesJs.insertionIndex(order, draggedType, pointer, baseCellWidth, baseCellHeight, spacing, columns);
    }

    function previewOrderOf(order, draggedType, index) {
        return QuickTogglesJs.previewOrderOf(order, draggedType, index);
    }

    function shiftsFor(currentOrder, previewOrder, draggedType, baseCellWidth, baseCellHeight, spacing, columns) {
        return QuickTogglesJs.shiftsFor(currentOrder, previewOrder, draggedType, baseCellWidth, baseCellHeight, spacing, columns);
    }

    function rowCount(order, columns) {
        return QuickTogglesJs.rowCount(order, columns);
    }
}
