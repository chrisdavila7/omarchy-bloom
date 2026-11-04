.pragma library
// Pure screen-coordinate geometry of the vertical layout (workspace column). No QML types: node-testable.
// The caller owns lifecycle, interpolation and interaction state. All coordinates are screen px.
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// Column of `count` slots (workspaces, then '+', then the gear). `breaks` lists the item indices that start a
// new group (an 8 px separator before them instead of the slot gap). The column is placed so the centre of
// the full rail is centred on (px, py) when unclamped, and slides only as far as needed to stay on screen.
function column(px, py, count, anchor, W, H, T, breaks) {
    var size = T.slotSize, gap = T.slotGap, sep = T.separator
    var offsets = [], isBreak = [], offset = 0
    for (var i = 0; i < count; i++) {
        var brk = i > 0 && breaks && breaks.indexOf(i) >= 0
        if (i > 0) offset += brk ? sep : gap
        isBreak.push(brk)
        offsets.push(offset); offset += size
    }
    anchor = clamp(anchor, 0, Math.max(0, count - 1))
    var m = T.edgeMargin
    var y = clamp(py - offset / 2, m, Math.max(m, H - m - offset))
    var x = clamp(px - size / 2, m, Math.max(m, W - m - size))
    return { x: x, y: y, width: size, height: offset, offsets: offsets, isBreak: isBreak, count: count, size: size,
             direction: (x + size / 2 <= W / 2) ? 1 : -1, anchor: anchor }
}
function itemCenter(L, i) {
    if (i < 0 || i >= L.count) return null
    return { x: L.x + L.size / 2, y: L.y + L.offsets[i] + L.size / 2 }
}
// Drawn rect of slot i (before hover widening): hairline (T.slotHair) gaps between neighbours in a group.
function slotRect(L, i, T) {
    var ext = (T.slotGap - T.slotHair) / 2
    var top = L.y + L.offsets[i], bot = top + L.size
    var topInner = i > 0 && !L.isBreak[i], botInner = i < L.count - 1 && !L.isBreak[i + 1]
    if (topInner) top -= ext
    if (botInner) bot += ext
    return { x: L.x, y: top, w: L.size, h: bot - top, topInner: topInner, botInner: botInner }
}
// Hit test. Vertical extents meet halfway across gaps/separators (no dead strips); the hovered slot is
// widened by T.hoverGrow toward the screen centre. Returns the item index or -1.
function hitTest(L, x, y, hovered, T) {
    for (var i = 0; i < L.count; i++) {
        var top = L.y + L.offsets[i], bot = top + L.size
        var yTop = i === 0 ? top : top - (L.offsets[i] - L.offsets[i - 1] - L.size) / 2
        var yBot = i === L.count - 1 ? bot : bot + (L.offsets[i + 1] - L.offsets[i] - L.size) / 2
        var extra = i === hovered ? T.hoverGrow : 0
        var left = L.x - (L.direction < 0 ? extra : 0)
        var right = L.x + L.width + (L.direction > 0 ? extra : 0)
        if (x >= left && x <= right && y >= yTop && y <= yBot) return i
    }
    return -1
}
// Outer (screen-centre-facing) edge x of the fully widened slot.
function edgeX(L, T) { return L.direction > 0 ? L.x + L.width + T.hoverGrow : L.x - T.hoverGrow }
// Where chips and their band spawn from: just inside the widened slot's centre-facing edge, at the slot's centre.
function spawnPoint(L, i, T) {
    var c = itemCenter(L, i)
    if (!c) return null
    return { x: edgeX(L, T) - L.direction * T.chipSpawnInset, y: c.y }
}
// Chip slots of item `index`: rows run horizontally from the slot toward the screen centre, centred on the
// slot, `T.chipRowPitch` apart. A row holds as many chips as fit between the slot and the far screen margin
// (capped at T.chipMaxCols); extra chips wrap to more rows, and the block of rows is shifted vertically to stay
// on screen. Returns [{x, y, row, inRow, amount}] (+ .rows = [{y, x0, x1, n}] band extents, .overflow).
function chipSlots(L, index, count, W, H, T) {
    var out = [], c = itemCenter(L, index)
    out.rows = []; out.overflow = false
    if (!c || count <= 0) return out
    var rad = T.chipSize / 2, pitch = T.chipSize + T.chipGap, dir = L.direction
    var mx = T.edgeMargin + rad, my = T.edgeMargin + T.railWidth / 2
    var first = edgeX(L, T) + dir * (T.chipEdgeGap + rad)
    var avail = dir > 0 ? (W - mx) - first : first - mx
    var cols = clamp(Math.floor(avail / pitch + 1e-9) + 1, 1, T.chipMaxCols)
    var rowsFit = Math.max(1, Math.floor((H - 2 * my) / T.chipRowPitch + 1e-9) + 1)
    var rows = Math.min(rowsFit, Math.ceil(count / cols))
    var span = (rows - 1) * T.chipRowPitch
    var y0 = clamp(c.y - span / 2, my, Math.max(my, H - my - span))
    var k = 0
    for (var r = 0; r < rows; r++) {
        var n = Math.min(cols, count - k), y = y0 + r * T.chipRowPitch
        for (var j = 0; j < n; j++, k++) out.push({ x: first + dir * j * pitch, y: y, ang: 0, r: 0, row: r, inRow: j, amount: n })
        var xa = first - dir * (rad + T.bandPad), xb = first + dir * (n - 1) * pitch + dir * (rad + T.bandPad)
        out.rows.push({ y: y, x0: Math.min(xa, xb), x1: Math.max(xa, xb), n: n })
    }
    out.overflow = k < count
    return out
}
// Nearest chip centre within `radius`, or -1. `allowed` (optional) excludes chips not hittable yet.
function chipHit(x, y, slots, radius, allowed) {
    var best = -1, bd = radius
    for (var i = 0; i < slots.length; i++) {
        if (allowed && !allowed[i]) continue
        var d = Math.hypot(x - slots[i].x, y - slots[i].y)
        if (d <= bd) { best = i; bd = d }
    }
    return best
}
// Pointer on the chips' band rows or the corridor between the slot's edge and the first band (padding `pad`).
function inReveal(L, index, slots, x, y, pad, T) {
    var c = itemCenter(L, index)
    if (!c || !slots.rows || slots.rows.length === 0) return false
    var e = edgeX(L, T), b0 = slots.rows[0], dir = L.direction
    var cx0 = Math.min(e, dir > 0 ? b0.x0 : b0.x1), cx1 = Math.max(e, dir > 0 ? b0.x0 : b0.x1)
    if (x >= cx0 && x <= cx1 && Math.abs(y - c.y) <= T.slotSize / 2) return true
    for (var i = 0; i < slots.rows.length; i++) {
        var R = slots.rows[i]
        if (x >= R.x0 - pad && x <= R.x1 + pad && Math.abs(y - R.y) <= T.railWidth / 2 + pad) return true
    }
    return false
}
