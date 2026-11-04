.pragma library
// Pure geometry for the Bloom. No QML types: unit-testable with node.
// Angles are screen angles (x = cos, y = sin, y down); "u" is arc length
// along the ring in [0, span], mapped to angle = start + dir * u.

var TAU = Math.PI * 2

function wrap(a) { a = (a + Math.PI) % TAU; if (a < 0) a += TAU; return a - Math.PI }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// The ring is always a complete circle: no edge fan / flip / partial arc. `rot` turns the whole ring (see ringRotation).
function fullArc(rot) { return { full: true, start: -Math.PI / 2 + (rot || 0), span: TAU, dir: 1 } }

// Ring scale: grows only when so many petals would be narrower than minPetalAngle.
function ringScale(n, T) { return Math.max(1, Math.min(T.maxScale, n * T.minPetalAngle / TAU)) }

// Outer radius the whole bloom can reach (grown petal incl. hover growth, plus the drift of the dial).
function ringExtent(n, T) { return T.outerR * ringScale(n, T) + T.hoverGrow + (T.driftMax || 0) }

// Hub position that keeps the WHOLE bloom (well + ring incl. hover growth) on screen inside margin m: the pointer
// position (cx, cy) is clamped inward by `ext` + m (centred on that axis if the screen is smaller than the bloom).
function hubClamp(cx, cy, ext, W, H, m) {
    var lo = ext + m
    return {
        x: W < 2 * lo ? W / 2 : clamp(cx, lo, W - lo),
        y: H < 2 * lo ? H / 2 : clamp(cy, lo, H - lo)
    }
}

// Returns [{a0,a1,mid,ri,ro,mag}] in absolute angles; a0<a1 when dir>0,
// a0>a1 when dir<0 is avoided by always emitting a0<a1 (sorted).
function nearArc(aimAngle, arc) {
    var mid = arc.start + arc.dir * arc.span / 2
    return mid + wrap(aimAngle - mid)
}

// Fixed angular spans (no magnifier). ro = resting outer radius; roH = outer radius when hovered (+T.hoverGrow).
function layout(n, arc, T, scale) {
    scale = scale || 1
    var b = arc.span / n, out = []
    for (var i = 0; i < n; i++) {
        var A = arc.start + arc.dir * i * b, B = arc.start + arc.dir * (i + 1) * b
        var lo = Math.min(A, B), hi = Math.max(A, B)
        out.push({ a0: lo, a1: hi, mid: (lo + hi) / 2, ri: T.innerR * scale, ro: T.outerR * scale, roH: T.outerR * scale + T.hoverGrow })
    }
    return out
}

// Stable hit test on the un-magnified layout. Returns index or -1.
function petalAt(r, ang, n, arc, T, k) {
    if (r < T.innerR * (k || 1) - T.hitSlop) return -1
    var b = arc.span / n
    var u = (nearArc(ang, arc) - arc.start) * arc.dir
    if (arc.full) u = ((u % TAU) + TAU) % TAU
    else if (u < 0 || u >= arc.span) return -1
    var i = Math.floor(u / b)
    return i >= 0 && i < n ? i : -1
}

// Drawn-wedge test (used by the self-check to compare against petalAt()).
function drawnIndexAt(r, ang, lay, T) {
    for (var i = 0; i < lay.length; i++) {
        var p = lay[i]
        if (r < p.ri - T.hitSlop || r > p.ro) continue
        var d = wrap(ang - p.mid)
        if (Math.abs(d) <= (p.a1 - p.a0) / 2 + 1e-9) return i
    }
    return -1
}

function pt(cx, cy, r, a) { return [cx + r * Math.cos(a), cy + r * Math.sin(a)] }
function f(v) { return (Math.round(v * 100) / 100).toString() }

// Annular sector with a constant-width hairline gap and rounded corners,
// as an SVG path in the coordinate space of (cx, cy). prog in 0..1 scales
// the radii out of the hub.
function petalPath(cx, cy, ri, ro, a0, a1, gap, cr) {
    var h = gap / 2
    var span = a1 - a0
    if (span <= 0 || ro <= ri + 2) return ""
    cr = Math.min(cr, (ro - ri) / 3, ri * span / 4)
    var n0 = [-Math.sin(a0), Math.cos(a0)], u0 = [Math.cos(a0), Math.sin(a0)]
    var n1 = [-Math.sin(a1), Math.cos(a1)], u1 = [Math.cos(a1), Math.sin(a1)]
    function edge(u, n, t, side) { return [cx + t * u[0] + side * h * n[0], cy + t * u[1] + side * h * n[1]] }
    var tOut = Math.sqrt(ro * ro - h * h), tIn = Math.sqrt(Math.max(0, ri * ri - h * h))
    var oS = pt(cx, cy, ro, a0 + (h + cr) / ro), oE = pt(cx, cy, ro, a1 - (h + cr) / ro)
    var iE = pt(cx, cy, ri, a1 - (h + cr) / ri), iS = pt(cx, cy, ri, a0 + (h + cr) / ri)
    var spO = (a1 - a0) - 2 * (h + cr) / ro
    var spI = (a1 - a0) - 2 * (h + cr) / ri
    var large = spO > Math.PI ? 1 : 0, largeI = spI > Math.PI ? 1 : 0
    var cO1 = edge(u1, n1, tOut, -1), L1 = edge(u1, n1, tOut - cr, -1)
    var L2 = edge(u1, n1, tIn + cr, -1), cI1 = edge(u1, n1, tIn, -1)
    var cI0 = edge(u0, n0, tIn, 1), L3 = edge(u0, n0, tIn + cr, 1)
    var L4 = edge(u0, n0, tOut - cr, 1), cO0 = edge(u0, n0, tOut, 1)
    return "M" + f(oS[0]) + " " + f(oS[1]) +
        " A" + f(ro) + " " + f(ro) + " 0 " + large + " 1 " + f(oE[0]) + " " + f(oE[1]) +
        " Q" + f(cO1[0]) + " " + f(cO1[1]) + " " + f(L1[0]) + " " + f(L1[1]) +
        " L" + f(L2[0]) + " " + f(L2[1]) +
        " Q" + f(cI1[0]) + " " + f(cI1[1]) + " " + f(iE[0]) + " " + f(iE[1]) +
        " A" + f(ri) + " " + f(ri) + " 0 " + largeI + " 0 " + f(iS[0]) + " " + f(iS[1]) +
        " Q" + f(cI0[0]) + " " + f(cI0[1]) + " " + f(L3[0]) + " " + f(L3[1]) +
        " L" + f(L4[0]) + " " + f(L4[1]) +
        " Q" + f(cO0[0]) + " " + f(cO0[1]) + " " + f(oS[0]) + " " + f(oS[1]) + " Z"
}

// Seam wedge: the petal's full angular wedge (no gap) with the outer corners rounded by `cr` and the inner corners
// sharp. Drawn with the petal (even-odd) so only the hairline gap and the corner notches are filled.
function seamPath(cx, cy, ri, ro, a0, a1, cr) {
    var span = a1 - a0
    if (span <= 0 || ro <= ri + 2) return ""
    cr = Math.min(cr, (ro - ri) / 3, ro * span / 4)
    var u0 = [Math.cos(a0), Math.sin(a0)], u1 = [Math.cos(a1), Math.sin(a1)]
    function along(u, t) { return [cx + t * u[0], cy + t * u[1]] }
    var oS = pt(cx, cy, ro, a0 + cr / ro), oE = pt(cx, cy, ro, a1 - cr / ro)
    var spO = span - 2 * cr / ro, large = spO > Math.PI ? 1 : 0, largeI = span > Math.PI ? 1 : 0
    var cO1 = along(u1, ro), L1 = along(u1, ro - cr), I1 = along(u1, ri)
    var I0 = along(u0, ri), L4 = along(u0, ro - cr), cO0 = along(u0, ro)
    return "M" + f(oS[0]) + " " + f(oS[1]) +
        " A" + f(ro) + " " + f(ro) + " 0 " + large + " 1 " + f(oE[0]) + " " + f(oE[1]) +
        " Q" + f(cO1[0]) + " " + f(cO1[1]) + " " + f(L1[0]) + " " + f(L1[1]) +
        " L" + f(I1[0]) + " " + f(I1[1]) +
        " A" + f(ri) + " " + f(ri) + " 0 " + largeI + " 0 " + f(I0[0]) + " " + f(I0[1]) +
        " L" + f(L4[0]) + " " + f(L4[1]) +
        " Q" + f(cO0[0]) + " " + f(cO0[1]) + " " + f(oS[0]) + " " + f(oS[1]) + " Z"
}


// Settings card placement (bloom). The card (w x h) attaches to the Settings petal: its centre sits on the petal's
// outward axis, pushed out just far enough that the card's nearest edge/corner is exactly `gap` from the ring's outer
// radius R (so the gap to the petal is cardGap whatever the axis angle). If that spot is off screen or would touch the
// ring after sliding it inside the margin `m`, the mirrored axis is tried, then axes fanned around the ring (nearest
// first). The first candidate whose clearance to the ring disc (centre cx,cy) is at least R + gap wins; otherwise the
// one with the largest clearance.
function rectClearance(cx, cy, x, y, w, h) {
    var nx = clamp(cx, x, x + w), ny = clamp(cy, y, y + h)
    return Math.hypot(cx - nx, cy - ny)
}
function cardPlace(cx, cy, R, ang, w, h, gap, W, H, m) {
    var cands = [ang, ang + Math.PI]
    for (var k = 1; k <= 23; k++) { cands.push(ang + k * Math.PI / 24); cands.push(ang - k * Math.PI / 24) }
    var best = null, want = R + gap
    for (var i = 0; i < cands.length; i++) {
        var a = cands[i], ux = Math.cos(a), uy = Math.sin(a)
        var lo = 0, hi = want + Math.hypot(w, h)
        for (var it = 0; it < 48; it++) {
            var t = (lo + hi) / 2
            if (rectClearance(cx, cy, cx + ux * t - w / 2, cy + uy * t - h / 2, w, h) >= want) hi = t; else lo = t
        }
        var x = cx + ux * hi - w / 2, y = cy + uy * hi - h / 2
        x = clamp(x, m, Math.max(m, W - w - m)); y = clamp(y, m, Math.max(m, H - h - m))
        var clear = rectClearance(cx, cy, x, y, w, h)
        var cand = { x: x, y: y, clear: clear, ang: a, index: i }
        if (clear >= want - 1e-6) return cand
        if (!best || clear > best.clear) best = cand
    }
    return best
}

// Distance from rect (x,y,w,h) to the outer arc (radius R) of the wedge a0..a1 around (cx, cy), sampled every ~0.5 deg.
function arcGap(cx, cy, R, a0, a1, x, y, w, h) {
    var best = Infinity, n = Math.max(2, Math.ceil((a1 - a0) / (0.5 * Math.PI / 180)))
    for (var i = 0; i <= n; i++) {
        var a = a0 + (a1 - a0) * i / n
        var px = cx + R * Math.cos(a), py = cy + R * Math.sin(a)
        var d = Math.hypot(px - clamp(px, x, x + w), py - clamp(py, y, y + h))
        if (d < best) best = d
    }
    return best
}
// Card centred on one axis angle, pushed out until it clears R + gap, slid inside the margin. Returns {x,y,clear,gap}
// where gap = distance from the card to the gear petal's outer arc (wedge a0..a1 at radius R).
function cardOnAxis(cx, cy, R, ang, a0, a1, w, h, gap, W, H, m) {
    var want = R + gap, ux = Math.cos(ang), uy = Math.sin(ang)
    var lo = 0, hi = want + Math.hypot(w, h)
    for (var it = 0; it < 48; it++) {
        var t = (lo + hi) / 2
        if (rectClearance(cx, cy, cx + ux * t - w / 2, cy + uy * t - h / 2, w, h) >= want) hi = t; else lo = t
    }
    var x = clamp(cx + ux * hi - w / 2, m, Math.max(m, W - w - m)), y = clamp(cy + uy * hi - h / 2, m, Math.max(m, H - h - m))
    return { x: x, y: y, clear: rectClearance(cx, cy, x, y, w, h), gap: arcGap(cx, cy, R, a0, a1, x, y, w, h) }
}
// Ring rotation (rad) that turns the whole ring just far enough that the Settings (last) petal has room for its card
// right beside its outer edge: the card must fit on screen on the petal's own axis, clear the ring by `gap`, and end
// up within `gap` (+ tol) of the petal's outer arc. Smallest |rotation| wins; of two equal ones, the card closer to the
// screen centre. 0 when the nominal position already works (or nothing works).
function ringRotation(hx, hy, n, R, w, h, gap, W, H, m, tol) {
    tol = tol === undefined ? 0.75 : tol
    var b = TAU / n, step = 2 * Math.PI / 180
    function ok(rot) {
        var mid = -Math.PI / 2 + rot + (n - 0.5) * b
        var p = cardOnAxis(hx, hy, R, mid, mid - b / 2, mid + b / 2, w, h, gap, W, H, m)
        return p.clear >= R + gap - 1e-6 && p.gap <= gap + tol ? p : null
    }
    if (ok(0)) return 0
    for (var k = 1; k * step <= Math.PI + 1e-9; k++) {
        var cand = []
        for (var sg = -1; sg <= 1; sg += 2) {
            var p = ok(sg * k * step)
            if (p) cand.push({ rot: sg * k * step, d: Math.hypot(p.x + w / 2 - W / 2, p.y + h / 2 - H / 2) })
        }
        if (cand.length) { cand.sort(function (a, c) { return a.d - c.d }); return cand[0].rot }
    }
    return 0
}

// Open arc path (for rails / edge highlight) between two angles.
function arcPath(cx, cy, r, a0, a1) {
    if (a1 - a0 < 0.002) a1 = a0 + 0.002
    var p = pt(cx, cy, r, a0), q = pt(cx, cy, r, a1)
    return "M" + f(p[0]) + " " + f(p[1]) + " A" + f(r) + " " + f(r) + " 0 " + ((a1 - a0) > Math.PI ? 1 : 0) + " 1 " + f(q[0]) + " " + f(q[1])
}

// Annular sector band (straight radial ends) between radii ri..ro, angles a0..a1
function bandPath(cx, cy, ri, ro, a0, a1) {
    if (a1 - a0 < 0.002) a1 = a0 + 0.002
    var large = (a1 - a0) > Math.PI ? 1 : 0
    var p = pt(cx, cy, ro, a0), q = pt(cx, cy, ro, a1), r = pt(cx, cy, ri, a1), s = pt(cx, cy, ri, a0)
    return "M" + f(p[0]) + " " + f(p[1]) + " A" + f(ro) + " " + f(ro) + " 0 " + large + " 1 " + f(q[0]) + " " + f(q[1]) +
        " L" + f(r[0]) + " " + f(r[1]) + " A" + f(ri) + " " + f(ri) + " 0 " + large + " 0 " + f(s[0]) + " " + f(s[1]) + " Z"
}

// Slots for window chips of one petal. Chips sit on arcs concentric with the dial centre (the hub, which is
// the origin of the returned x/y): row 0 at radius rc (just beyond the hovered petal's grown outer edge), extra
// rows (overflow) at rc + row * chipRowStep. Neighbouring chips are a constant arc length apart
// (chipSize + chipGap), fanned symmetrically around `mid`. A row holds at most chipMaxSpanDeg of arc and at
// most what stays on screen at its radius. If the fan would leave the screen, the whole fan's centre angle
// is shifted to the nearest angle where it fits (smallest |shift|; least-violating if none fits).
// hx, hy = hub position on screen, W, H = screen size. Returns [{x,y,ang,r,row,inRow,amount}] plus .shift
function chipSlots(count, mid, rc, hx, hy, W, H, T) {
    var out = []
    out.shift = 0
    if (count <= 0) return out
    var pitch = T.chipSize + T.chipGap
    var maxSpan = T.chipMaxSpanDeg * Math.PI / 180
    var m = T.edgeMargin + T.railWidth / 2
    function off(x, y) {
        return Math.max(0, m - x) + Math.max(0, x - (W - m)) + Math.max(0, m - y) + Math.max(0, y - (H - m))
    }
    // rows: capacity from the span limit and from the widest on-screen run at that radius
    var rows = [], left = count, row = 0
    while (left > 0) {
        var r = rc + row * T.chipRowStep, dth = pitch / r
        var N = 720, st = TAU / N, run = 0, best = 0, all = true, first = -1
        for (var k = 0; k < 2 * N; k++) {
            var a = (k % N) * st
            if (off(hx + r * Math.cos(a), hy + r * Math.sin(a)) <= 0.5) { run++; if (run > best) best = run } else { run = 0; all = false }
        }
        var avail = all ? TAU : Math.max(0, Math.min(best, N) - 1) * st
        var cap = Math.max(1, Math.floor(Math.min(maxSpan, avail) / dth + 1e-9) + 1)
        var n = Math.min(cap, left)
        rows.push({ r: r, dth: dth, n: n }); left -= n; row++
    }
    function violation(shift) {
        var v = 0
        for (var ri = 0; ri < rows.length; ri++) {
            var R = rows[ri]
            for (var i = 0; i < R.n; i++) {
                var a = mid + shift + (i - (R.n - 1) / 2) * R.dth
                v += off(hx + R.r * Math.cos(a), hy + R.r * Math.sin(a))
            }
        }
        return v
    }
    var bestShift = 0, bestV = violation(0)
    if (bestV > 1) {
        var step = 0.25 * Math.PI / 180
        for (var s = 1; s * step <= Math.PI && bestV > 1; s++) {
            for (var sg = -1; sg <= 1; sg += 2) {
                var vv = violation(sg * s * step)
                if (vv < bestV - 1e-6) { bestV = vv; bestShift = sg * s * step }
            }
        }
    }
    out.shift = bestShift
    for (var ri2 = 0; ri2 < rows.length; ri2++) {
        var R2 = rows[ri2]
        for (var i2 = 0; i2 < R2.n; i2++) {
            var a2 = mid + bestShift + (i2 - (R2.n - 1) / 2) * R2.dth
            out.push({ x: R2.r * Math.cos(a2), y: R2.r * Math.sin(a2), ang: a2, r: R2.r, row: ri2, inRow: i2, amount: R2.n })
        }
    }
    return out
}

// Polar hit test of chips (origin = dial centre): the chip whose centre is nearest to (r, ang) and within
// `rad` px, or -1. `allowed` (optional array of booleans) excludes chips that aren't hittable yet.
function chipHit(r, ang, slots, rad, allowed) {
    var best = -1, bd = rad
    for (var j = 0; j < slots.length; j++) {
        if (allowed && !allowed[j]) continue
        var s = slots[j], da = wrap(ang - s.ang)
        var d = Math.sqrt(Math.max(0, r * r + s.r * s.r - 2 * r * s.r * Math.cos(da)))
        if (d <= bd) { bd = d; best = j }
    }
    return best
}

function smooth(t) { t = clamp(t, 0, 1); return t * t * (3 - 2 * t) }

// Layout-interface helpers (the vertical layout implements the same names in ColumnGeometry.js).
// Where a window dropped on petal i vanishes into: the petal's outer edge midpoint (hub-relative origin cx, cy).
function landingPoint(cx, cy, lay, i) { return lay[i] ? pt(cx, cy, lay[i].roH, lay[i].mid) : null }
// Where chips spawn from (hub-relative polar): just inside the grown petal's outer edge.
function spawnPoint(lay, i, T) { return lay[i] ? { a: lay[i].mid, r: lay[i].roH - T.chipSpawnInset } : null }
