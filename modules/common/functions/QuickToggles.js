// Geometry for the Android-style quick toggle grid.
//
// The toggle panel packs the user's configured toggles into rows of
// `columns` cells, and while a tile is dragged the other tiles have to
// glide aside to open a gap at the drop position. All of that needs the
// same arithmetic: where every tile sits for a given order. Keeping it
// here, away from the scene graph, is what lets it be tested — the panel
// used to walk the live RowLayout children to find neighbours, which
// broke the moment ButtonGroup gained a WindowGlass child.

// Pack toggles into rows, greedily filling each row to `columns` cells.
// Mirrors the panel's row layout: a toggle larger than the remaining
// space starts a new row. Empty rows are dropped so they take no space.
function packRows(toggles, columns) {
    const rows = [];
    let row = [];
    let total = 0;
    for (const toggle of toggles) {
        if (!toggle) continue;
        const size = toggle.size;
        if (total + size > columns && row.length > 0) {
            rows.push(row);
            row = [];
            total = 0;
        }
        row.push(toggle);
        total += size;
    }
    if (row.length > 0) rows.push(row);
    return rows;
}

// Width of one tile: `size` cells plus the spacing between them, the
// same formula GroupButton uses for baseWidth.
function tileWidth(size, baseCellWidth, spacing) {
    return baseCellWidth * size + spacing * (size - 1);
}

// Width a row actually needs: every tile plus the gaps between them.
function rowWidth(row, baseCellWidth, spacing) {
    if (!row || row.length === 0) return 0;
    let total = 0;
    for (const toggle of row) {
        total += tileWidth(toggle.size, baseCellWidth, spacing);
    }
    return total + spacing * (row.length - 1);
}

// Where every tile of `order` sits, keyed by type: {x, y, w, h} in
// grid space (origin = top-left of the first row). Rows are laid out
// by a Column, so a tile's y is the summed height of the rows above
// it; x accumulates tile widths plus spacing across its row.
function slotRects(order, columns, baseCellWidth, baseCellHeight, spacing) {
    const rects = {};
    let y = 0;
    for (const row of packRows(order, columns)) {
        let x = 0;
        for (const toggle of row) {
            const w = tileWidth(toggle.size, baseCellWidth, spacing);
            rects[toggle.type] = { x: x, y: y, w: w, h: baseCellHeight };
            x += w + spacing;
        }
        y += baseCellHeight + spacing;
    }
    return rects;
}

// The index at which the dragged tile would land so that its slot
// centre is nearest the pointer. Tries every insertion point in the
// order with the dragged tile removed and picks the closest one.
function insertionIndex(order, draggedType, pointer, baseCellWidth, baseCellHeight, spacing, columns) {
    const rest = order.filter(t => t && t.type !== draggedType);
    const dragged = order.find(t => t && t.type === draggedType);
    if (!dragged) return -1;
    let best = 0;
    let bestDist = Infinity;
    for (let k = 0; k <= rest.length; k++) {
        const candidate = rest.slice();
        candidate.splice(k, 0, dragged);
        const rect = slotRects(candidate, columns, baseCellWidth, baseCellHeight, spacing)[draggedType];
        if (!rect) continue;
        const dx = pointer.x - (rect.x + rect.w / 2);
        const dy = pointer.y - (rect.y + rect.h / 2);
        const dist = dx * dx + dy * dy;
        if (dist < bestDist) {
            bestDist = dist;
            best = k;
        }
    }
    return best;
}

// Build the preview order: remove the dragged tile, re-insert it at
// `index` within the remaining tiles.
function previewOrderOf(order, draggedType, index) {
    const rest = order.filter(t => t && t.type !== draggedType);
    const dragged = order.find(t => t && t.type === draggedType);
    if (!dragged) return order.slice();
    rest.splice(Math.max(0, Math.min(index, rest.length)), 0, dragged);
    return rest;
}

// Per-tile glide offsets between two orders, keyed by type:
// {dx, dy}. The dragged tile is excluded — it follows the pointer.
function shiftsFor(currentOrder, previewOrder, draggedType, baseCellWidth, baseCellHeight, spacing, columns) {
    const now = slotRects(currentOrder, columns, baseCellWidth, baseCellHeight, spacing);
    const next = slotRects(previewOrder, columns, baseCellWidth, baseCellHeight, spacing);
    const shifts = {};
    for (const type of Object.keys(next)) {
        if (type === draggedType) continue;
        const a = now[type];
        const b = next[type];
        if (!a || !b) continue;
        shifts[type] = { dx: b.x - a.x, dy: b.y - a.y };
    }
    return shifts;
}

// Number of rows an order needs — drives the panel's height while a
// preview packing needs more rows than the current one.
function rowCount(order, columns) {
    return packRows(order, columns).length;
}
