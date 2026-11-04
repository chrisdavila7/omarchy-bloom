// node test_column_geometry.js -- vertical layout geometry: slot positions, anchoring, clamping, hit-testing, chip rows
const fs = require('fs'), vm = require('vm'), path = require('path'), assert = require('assert')
const src = fs.readFileSync(path.join(__dirname, '../ColumnGeometry.js'), 'utf8').replace(/^\.pragma.*$/m, '')
const ctx = {}; vm.runInNewContext(src + ';this.api={column,itemCenter,slotRect,hitTest,edgeX,spawnPoint,chipSlots,chipHit,inReveal,cardPlace}', ctx)
const c = ctx.api
const T = { slotSize: 40, slotGap: 3, slotHair: 2, separator: 8, edgeMargin: 8, hoverGrow: 6, chipSize: 34, chipGap: 6, railWidth: 40,
            chipEdgeGap: 7, chipMaxCols: 8, chipRowPitch: 42, bandPad: 3, chipSpawnInset: 10 }
let checks = 0
const ok = (cond, msg) => { checks++; assert(cond, msg) }
const W = 1280, H = 800
const A0 = { x0: 0, y0: 0, x1: W, y1: H }
// geometry of counts 6 (5 ws + Settings) .. 11, with/without a guest group (Settings slot follows a separator)
const cases = []
for (const n of [6, 7, 8, 10, 11]) for (const guest of [-1, 5]) cases.push({ n, breaks: guest >= 0 && guest < n - 1 ? [guest, n - 1] : [n - 1] })
let layouts = 0
for (const { n, breaks } of cases) {
  // rail center under pointer when unclamped
  for (let cur = 0; cur < n; cur++) {
    const L0 = c.column(640, 400, n, cur, A0, T, breaks)
    const cc = { x: L0.x + L0.width / 2, y: L0.y + L0.height / 2 }
    const unclamped = L0.y > T.edgeMargin + 1e-9 && L0.y + L0.height < H - T.edgeMargin - 1e-9
    if (unclamped) { ok(Math.abs(cc.y - 400) < 1e-9, `rail ${cur}/${n} not under pointer`); ok(Math.abs(cc.x - 640) < 1e-9, 'x not under pointer') }
  }
  // spots: positions incl. corners and edges
  for (const [px, py] of [[640, 400], [4, 4], [1276, 4], [4, 796], [1276, 796], [640, 2], [640, 798], [2, 400], [1278, 400], [100, 700], [1200, 100]]) {
    for (const cur of [0, 2, n - 1]) {
      const L = c.column(px, py, n, cur, A0, T, breaks); layouts++
      ok(L.x >= T.edgeMargin - 1e-9 && L.x + L.width <= W - T.edgeMargin + 1e-9, `x on screen ${px},${py}`)
      ok(L.y >= T.edgeMargin - 1e-9 && L.y + L.height <= H - T.edgeMargin + 1e-9, `y on screen ${px},${py},n=${n}`)
      ok(L.direction === (L.x + L.width / 2 <= W / 2 ? 1 : -1), 'direction toward centre')
      // offsets monotone, spacing gap / separator
      for (let i = 1; i < n; i++) {
        const d = L.offsets[i] - L.offsets[i - 1] - T.slotSize
        ok(Math.abs(d - (breaks.includes(i) ? T.separator : T.slotGap)) < 1e-9, `spacing at ${i}`)
      }
      // slot rects: no overlaps, hairline gaps of exactly slotHair inside groups
      for (let i = 0; i < n; i++) {
        const r = c.slotRect(L, i, T)
        if (i > 0) { const q = c.slotRect(L, i - 1, T), gap = r.y - (q.y + q.h); ok(Math.abs(gap - (breaks.includes(i) ? T.separator : T.slotHair)) < 1e-9, `hairline ${i}: ${gap}`) }
      }
      // hit test: every slot centre, widened hover edge, outside misses, no dead strips along the centre line
      for (let i = 0; i < n; i++) {
        const ct = c.itemCenter(L, i)
        ok(c.hitTest(L, ct.x, ct.y, -1, T) === i, `hit centre ${i}`)
        ok(c.hitTest(L, ct.x, ct.y, i, T) === i, `hit centre hovered ${i}`)
        const out = L.direction > 0 ? L.x + L.width + 3 : L.x - 3
        ok(c.hitTest(L, out, ct.y, -1, T) === -1, `outside edge not hit ${i}`)
        ok(c.hitTest(L, out, ct.y, i, T) === i, `widened slot hit ${i}`)
        ok(c.hitTest(L, out, ct.y, i === 0 ? 1 : i - 1, T) === -1, 'neighbour does not widen this slot')
        const far = L.direction > 0 ? L.x + L.width + T.hoverGrow + 1 : L.x - T.hoverGrow - 1
        ok(c.hitTest(L, far, ct.y, i, T) === -1, 'beyond widened edge misses')
      }
      for (let y = L.y; y <= L.y + L.height; y += 0.5) ok(c.hitTest(L, L.x + L.width / 2, y, -1, T) >= 0, `dead strip at y=${y}`)
      ok(c.hitTest(L, L.x + L.width / 2, L.y - 1, -1, T) === -1 && c.hitTest(L, L.x + L.width / 2, L.y + L.height + 1, -1, T) === -1, 'outside column')
      // chips: rows on screen, centre-ward, no overlaps, hit-testable, band extents cover chips
      for (const idx of [0, Math.min(2, n - 2), n - 2]) for (const cnt of [1, 3, 8, 9, 17, 40]) {
        const S = c.chipSlots(L, idx, cnt, A0, T)
        ok(S.length === Math.min(cnt, S.length) && S.length > 0, 'slots exist')
        if (!S.overflow) ok(S.length === cnt, `all chips placed ${cnt} got ${S.length}`)
        const first = c.spawnPoint(L, idx, T)
        for (let i = 0; i < S.length; i++) {
          ok(S[i].x >= T.edgeMargin + 17 - 1e-6 && S[i].x <= W - T.edgeMargin - 17 + 1e-6, `chip x on screen ${S[i].x}`)
          ok(S[i].y >= T.edgeMargin + 20 - 1e-6 && S[i].y <= H - T.edgeMargin - 20 + 1e-6, `chip y on screen ${S[i].y}`)
          ok(L.direction > 0 ? S[i].x > L.x + L.width + T.hoverGrow : S[i].x < L.x - T.hoverGrow, 'chips beyond slot, toward centre')
          ok(c.chipHit(S[i].x, S[i].y, S, 19) === i, 'chip hit')
          ok(c.chipHit(S[i].x, S[i].y, S, 19, S.map(() => false)) === -1, 'not hittable until revealed')
          for (let j = 0; j < i; j++) ok(Math.hypot(S[i].x - S[j].x, S[i].y - S[j].y) >= T.chipSize + T.chipGap - 1e-6 || Math.abs(S[i].y - S[j].y) >= T.chipRowPitch - 1e-6 , `chips overlap ${i},${j}`)
          ok(S[i].inRow < T.chipMaxCols, 'row width cap')
        }
        // rows do not overlap each other vertically (bands) and stay on screen
        for (let r = 0; r < S.rows.length; r++) {
          ok(S.rows[r].y - T.railWidth / 2 >= T.edgeMargin - 1e-6 && S.rows[r].y + T.railWidth / 2 <= H - T.edgeMargin + 1e-6, 'band on screen')
          ok(S.rows[r].x0 >= T.edgeMargin - 1e-6 && S.rows[r].x1 <= W - T.edgeMargin + 1e-6, 'band within screen x')
          if (r > 0) ok(S.rows[r].y - S.rows[r - 1].y >= T.railWidth - 1e-6, 'bands do not overlap')
        }
        ok(c.inReveal(L, idx, S, S[0].x, S[0].y, 10, T), 'reveal covers chips')
        ok(c.inReveal(L, idx, S, (L.direction > 0 ? L.x + L.width + T.hoverGrow + 3 : L.x - T.hoverGrow - 3), c.itemCenter(L, idx).y, 10, T), 'reveal covers corridor')
        ok(!c.inReveal(L, idx, S, L.x + L.width / 2, L.y - 30, 10, T), 'reveal excludes far points')
        ok(first && Math.abs(first.y - c.itemCenter(L, idx).y) < 1e-9, 'spawn on slot centre line')
      }
    }
  }
}

// ---- settings card placement (vertical): beside the Settings slot, never over the column, always on screen -----
{
  const GAP = 10, M = 12, ch = 76
  let n = 0, same = 0, other = 0
  for (const w of [206, 240]) for (const { n: cnt, breaks } of cases) {
    for (const [px, py] of [[640, 400], [4, 4], [1276, 4], [4, 796], [1276, 796], [640, 2], [640, 798], [2, 400], [1278, 400], [100, 700], [1200, 100], [30, 400], [1250, 400]]) {
      for (const cur of [0, cnt - 1]) {
        const L = c.column(px, py, cnt, cur, A0, T, breaks), i = cnt - 1
        const p = c.cardPlace(L, i, w, ch, GAP, A0, M), tag = `n=${cnt} @${px},${py} w=${w}`
        n++
        ok(p.x >= M - 1e-9 && p.x + w <= W - M + 1e-9 && p.y >= M - 1e-9 && p.y + ch <= H - M + 1e-9, `card on screen ${tag}`)
        const overlapX = p.x < L.x + L.width + T.hoverGrow && p.x + w > L.x - T.hoverGrow
        ok(!overlapX, `card clear of the column incl. hover widening ${tag}`)
        const cy = c.itemCenter(L, i).y
        ok(p.y <= cy && p.y + ch >= cy, `card spans the gear slot's centre line ${tag}`)
        if (p.side === L.direction) {
          same++
          const edge = L.direction > 0 ? L.x + L.width : L.x
          ok(Math.abs(Math.abs(p.x - edge) - (L.direction > 0 ? GAP : w + GAP)) < 1e-9 || Math.abs((L.direction > 0 ? p.x - edge : edge - (p.x + w)) - GAP) < 1e-9, `gap on the centre side ${tag}`)
        } else other++
      }
    }
  }
  { // mirrored branch: force a column whose centre-facing side is too tight (direction pointing at the near edge)
    const GAP = 10, M = 12, w = 206
    for (const [dir, px] of [[1, 1240], [-1, 40]]) {
      const L = Object.assign({}, c.column(px, 400, 7, 0, A0, T, [6]), { direction: dir }), i = 6
      const p = c.cardPlace(L, i, w, ch, GAP, A0, M)
      ok(p.side === -dir, `mirrored side taken (dir ${dir})`)
      ok(p.x >= M && p.x + w <= W - M, 'mirrored card on screen')
      ok(p.x + w <= L.x - T.hoverGrow || p.x >= L.x + L.width + T.hoverGrow, 'mirrored card clear of the column')
      const gapPx = dir > 0 ? L.x - (p.x + w) : p.x - (L.x + L.width)
      ok(Math.abs(gapPx - GAP) < 1e-9, `mirrored card keeps cardGap (${gapPx})`)
    }
  }
  // measured card-to-slot gap on the real (centre) side, all corners / edges / centre
  { let worst = 0
    for (const [px, py] of [[640, 400], [4, 4], [1276, 4], [4, 796], [1276, 796], [640, 2], [640, 798], [2, 400], [1278, 400]]) for (const { n: cnt, breaks } of cases) {
      const L = c.column(px, py, cnt, 0, A0, T, breaks), p = c.cardPlace(L, cnt - 1, 207, ch, GAP, A0, M)
      const g2 = p.side > 0 ? p.x - (L.x + L.width) : L.x - (p.x + 207); worst = Math.max(worst, Math.abs(g2 - GAP))
      ok(Math.abs(g2 - GAP) < 1e-9, `card gap ${g2} @${px},${py}`)
    }
    console.log('vertical card gap deviates from cardGap by at most ' + worst.toFixed(3) + ' px') }
  console.log(`column card placement: ${n} cases (${same} toward centre, ${other} mirrored)`)
}
// ---- reserved areas: column, chip rows and card stay inside the usable area (screen minus Omarchy's bar)
{
  const insets = { 'left bar 48': [48, 0, 0, 0], 'left 36': [36, 0, 0, 0], 'top bar 30': [0, 30, 0, 0], 'left+top': [48, 30, 0, 0], 'right+bottom': [0, 0, 40, 28], 'all four': [36, 24, 36, 24] }
  const M = 12, GAP = 10, ch = 76, cw = [207, 240]
  let n = 0
  for (const [iname, [l, t, r, b]] of Object.entries(insets)) {
    const A = { x0: l, y0: t, x1: W - r, y1: H - b }
    for (const { n: cnt, breaks } of cases) for (const [px, py] of [[640, 400], [4, 4], [4, 400], [4, 796], [1276, 4], [1276, 796], [640, 2], [640, 798], [1278, 400], [60, 60], [30, 300]]) {
      const L = c.column(px, py, cnt, 0, A, T, breaks), tag = `${iname} n=${cnt} @${px},${py}`
      ok(L.x >= A.x0 + T.edgeMargin - 1e-9 && L.x + L.width <= A.x1 - T.edgeMargin + 1e-9, `${tag} column x inside`)
      ok(L.y >= A.y0 + T.edgeMargin - 1e-9 && L.y + L.height <= A.y1 - T.edgeMargin + 1e-9, `${tag} column y inside`)
      ok(L.direction === (L.x + L.width / 2 <= (A.x0 + A.x1) / 2 ? 1 : -1), `${tag} direction toward the usable centre`)
      // hover-widened slot and chip rows
      for (const i of [0, Math.floor(cnt / 2), cnt - 1]) {
        ok(c.edgeX(L, T) >= A.x0 + T.edgeMargin - 1e-9 && c.edgeX(L, T) <= A.x1 - T.edgeMargin + 1e-9, `${tag} widened slot inside`)
        for (const k of [1, 5, 12, 30]) {
          const S = c.chipSlots(L, i, k, A, T)
          for (const q of S) {
            ok(q.x - T.chipSize / 2 >= A.x0 + T.edgeMargin - 1e-6 && q.x + T.chipSize / 2 <= A.x1 - T.edgeMargin + 1e-6, `${tag} chip x inside (${q.x})`)
            ok(q.y - T.railWidth / 2 >= A.y0 + T.edgeMargin - 1e-6 && q.y + T.railWidth / 2 <= A.y1 - T.edgeMargin + 1e-6, `${tag} chip row inside (${q.y})`)
          }
        }
      }
      for (const w of cw) {
        const p = c.cardPlace(L, cnt - 1, w, ch, GAP, A, M)
        ok(p.x >= A.x0 + M - 1e-9 && p.x + w <= A.x1 - M + 1e-9 && p.y >= A.y0 + M - 1e-9 && p.y + ch <= A.y1 - M + 1e-9, `${tag} card inside usable area`)
        ok(p.x + w <= L.x - 0 + 1e-9 || p.x >= L.x + L.width - 1e-9, `${tag} card never over the column`)
        n++
      }
    }
  }
  // left bar: a column asked for at the very left edge sits right of the bar
  const A = { x0: 48, y0: 0, x1: W, y1: H }, L = c.column(4, 400, 7, 0, A, T, [6])
  ok(L.x === 48 + T.edgeMargin, 'left bar: column x = bar + margin')
  ok(c.cardPlace(L, 6, 207, ch, GAP, A, M).x >= 48 + M, 'left bar: card clear of the bar')
  console.log(`reserved-area column checks: ${n} card placements over ${Object.keys(insets).length} inset sets`)
}
console.log(`column geometry: ${checks} checks, ${layouts} layouts, 0 failures`)
