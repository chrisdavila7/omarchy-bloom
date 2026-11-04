// node test_geometry.js  -- polar hit-testing vs drawn wedges, fixed spans + edge-flip
const fs = require('fs'), path = require('path'), vm = require('vm')
const src = fs.readFileSync(path.join(__dirname, '../Geometry.js'), 'utf8').replace(/^\.pragma.*$/m, '')
const G = {}; vm.runInNewContext(src + ';this.G={arcFor,layout,petalAt,drawnIndexAt,petalPath,seamPath,cardPlace,rectClearance,chipSlots,chipHit,wrap}', G)
const g = G.G
const T = { innerR: 40, outerR: 92, hoverGrow: 6, maxScale: 1.7, hitSlop: 4, minPetalAngle: 0.42,
            fitRadius: 128, edgeMargin: 8, chipSize: 34, chipGap: 6, chipMaxSpanDeg: 150, chipRowStep: 44, chipEdgeGap: 7, railWidth: 40 }
const W = 1280, H = 800
let fails = 0, checks = 0
const ok = (c, m) => { checks++; if (!c) { fails++; console.log('FAIL', m) } }

const spots = { center: [640, 400], top: [640, 20], bottom: [640, 785], left: [10, 400], right: [1270, 400],
                tl: [12, 12], tr: [1268, 12], bl: [12, 788], br: [1268, 788], nearTop: [300, 120] }
for (const n of [6, 7, 9]) for (const [name, [x, y]] of Object.entries(spots)) {
  const arc = g.arcFor(x, y, W, H, n, T)
  // arc stays on screen at the fit radius (or all-angles fallback)
  if (!arc.full) for (let u = 0; u <= arc.span; u += 0.05) {
    const a = arc.start + arc.dir * u, px = x + T.fitRadius * 0.66 * Math.cos(a), py = y + T.fitRadius * 0.66 * Math.sin(a)
    ok(px >= -1 && px <= W + 1 && py >= -1 && py <= H + 1, `${name} n=${n} arc leaves screen at u=${u.toFixed(2)}`)
  }
  const b = arc.span / n, K = Math.max(1, Math.min(T.maxScale, n * T.minPetalAngle / arc.span))
  for (const strength of [0, 1]) for (let i = 0; i < n; i++) {
    const aim = arc.start + arc.dir * (i + 0.5) * b
    const lay = g.layout(n, arc, T, K)
    // monotone, contiguous, total span preserved
    let total = 0
    for (let k = 0; k < n; k++) { ok(lay[k].a1 > lay[k].a0, `${name} n=${n} s=${strength} petal ${k} degenerate`); total += lay[k].a1 - lay[k].a0 }
    ok(Math.abs(total - arc.span) < 1e-6, `${name} n=${n} total span ${total} != ${arc.span}`)
    // no magnifier: every petal has the same fixed angular span, resting radius and hovered radius +hoverGrow
    for (let k = 0; k < n; k++) {
      ok(Math.abs((lay[k].a1 - lay[k].a0) - b) < 1e-9, `${name} n=${n} petal ${k} span changed`)
      ok(Math.abs(lay[k].ro - T.outerR * K) < 1e-9 && Math.abs(lay[k].roH - (T.outerR * K + 6)) < 1e-9, `${name} n=${n} petal ${k} radii`)
      ok(Math.abs(lay[k].mid - (arc.start + arc.dir * (k + 0.5) * b)) < 1e-9, `${name} n=${n} petal ${k} mid`)
    }
    // hit test (base layout) at the aim equals i, and the drawn wedge agrees at the petal centre
    const r = (T.innerR + T.outerR) / 2 * K
    ok(g.petalAt(r, aim, n, arc, T, K) === i, `${name} n=${n} petalAt centre ${i}`)
    ok(g.drawnIndexAt(r, aim, lay, T) === i, `${name} n=${n} s=${strength} drawn wedge at centre ${i}`)
  }
  // random pointers: drawn vs base index mismatch should be limited to near-boundary cases
  let mism = 0, tot = 0
  for (let t = 0; t < 400; t++) {
    const aim = (Math.random() * 2 - 1) * Math.PI, ang = aim + (Math.random() - 0.5) * 0.3
    const lay = g.layout(n, arc, T, K), r = 60 * K
    const bi = g.petalAt(r, ang, n, arc, T), di = g.drawnIndexAt(r, ang, lay, T)
    if (bi >= 0 && di >= 0) { tot++; if (bi !== di) mism++ }
  }
  console.log(`${name.padEnd(7)} n=${n} ${arc.full ? 'full ' : 'arc  '}K=${K.toFixed(2)} span=${(arc.span*180/Math.PI).toFixed(0)}deg dir=${arc.dir} base-vs-drawn mismatch ${(100*mism/Math.max(1,tot)).toFixed(1)}%`)
}
// path strings are well formed
const lay = g.layout(7, { full: true, start: -Math.PI/2, span: 2*Math.PI, dir: 1 }, T, 1)
for (const p of lay) { const d = g.petalPath(100, 100, p.ri, p.ro, p.a0, p.a1, 2, 7); ok(/^M[\d. -]+A/.test(d) && !/NaN/.test(d), 'petalPath ' + d.slice(0, 40)) }

// ---- chip arc layout ------------------------------------------------------------------------------
{
  const pitch = T.chipSize + T.chipGap, margin = T.edgeMargin + T.railWidth / 2
  const clampHub = (x, y) => [Math.max(28, Math.min(W - 28, x)), Math.max(28, Math.min(H - 28, y))]
  const maxSpan = T.chipMaxSpanDeg * Math.PI / 180
  let nOff = 0, nTot = 0, nShift = 0
  for (const [name, [x0, y0]] of Object.entries(spots)) {
    const [hx, hy] = clampHub(x0, y0)
    for (const n of [6, 7]) {
      const arc = g.arcFor(hx, hy, W, H, n, T)
      const K = Math.max(1, Math.min(T.maxScale, n * T.minPetalAngle / arc.span))
      const rc = (T.outerR * K + T.hoverGrow) + T.chipEdgeGap + T.chipSize / 2
      for (let pi = 0; pi < n; pi++) {
        const mid = arc.start + arc.dir * (pi + 0.5) * arc.span / n
        for (let cnt = 1; cnt <= 14; cnt++) {
          const s = g.chipSlots(cnt, mid, rc, hx, hy, W, H, T), tag = `${name} n=${n} petal ${pi} cnt=${cnt}`
          ok(s.length === cnt, `${tag} slot count ${s.length}`)
          nTot++
          // concentric: every chip on a circle around the hub, radius rc + row*step; row 0 is the petal arc
          for (const c of s) {
            ok(Math.abs(Math.hypot(c.x, c.y) - c.r) < 1e-6, `${tag} chip not at its radius`)
            ok(Math.abs(c.r - (rc + c.row * T.chipRowStep)) < 1e-6, `${tag} chip radius`)
            // clear of the swollen petal: inner chip edge beyond outer edge by ~chipEdgeGap
            const edge = (T.outerR * K + T.hoverGrow)
            ok(c.r - T.chipSize / 2 >= edge + T.chipEdgeGap - 1e-6 && c.r - T.chipSize / 2 <= edge + T.chipEdgeGap + T.chipRowStep * 14, `${tag} chip overlaps petal`)
          }
          ok(Math.abs(s[0].r - T.chipSize / 2 - (T.outerR * K + T.hoverGrow) - T.chipEdgeGap) < 1e-6, `${tag} edge gap not 7px`)
          // no overlaps; constant arc pitch between neighbours in a row; fan <= max span
          for (let a = 0; a < cnt; a++) for (let b = a + 1; b < cnt; b++)
            ok(Math.hypot(s[a].x - s[b].x, s[a].y - s[b].y) >= T.chipSize + 2, `${tag} chips ${a},${b} overlap`)
          for (let a = 1; a < cnt; a++) if (s[a].row === s[a - 1].row)
            ok(Math.abs(Math.abs(g.wrap(s[a].ang - s[a - 1].ang)) * s[a].r - pitch) < 1e-6, `${tag} pitch not constant`)
          const row0 = s.filter(c => c.row === 0)
          ok((row0.length - 1) * pitch / rc <= maxSpan + 1e-9, `${tag} row 0 fans beyond max span`)
          // symmetric around the petal centre when the fan was not shifted
          if (Math.abs(s.shift) < 1e-12) for (const row of new Set(s.map(c => c.row))) {
            const rr = s.filter(c => c.row === row), c0 = rr.reduce((p, c) => p + c.ang, 0) / rr.length
            ok(Math.abs(g.wrap(c0 - mid)) < 1e-9, `${tag} row ${row} not symmetric about petal centre`)
          }
          // on screen (center fan within the edge margin) -- required whenever the unshifted fan fits at all
          const offs = s.map(c => { const px = hx + c.x, py = hy + c.y; return Math.max(0, margin - px, px - (W - margin), margin - py, py - (H - margin)) })
          const worst = Math.max(...offs)
          if (cnt <= 4 || name === 'center') ok(worst <= 1.0, `${tag} chip off screen by ${worst.toFixed(1)}px (shift ${(s.shift*180/Math.PI).toFixed(1)}deg)`)
          if (worst > 1.0) nOff++
          if (Math.abs(s.shift) > 1e-9) nShift++
          // shifted fan stays as close to centred as possible: backing off 1 deg toward the petal centre puts a chip off screen
          if (Math.abs(s.shift) > 2 * Math.PI / 180 && worst <= 1.0) {
            const d = -Math.sign(s.shift) * Math.PI / 180
            const back = s.map(c => { const a2 = c.ang + d, px = hx + c.r * Math.cos(a2), py = hy + c.r * Math.sin(a2); return Math.max(0, margin - px, px - (W - margin), margin - py, py - (H - margin)) })
            ok(Math.max(...back) > 0.5, `${tag} shift ${(s.shift*180/Math.PI).toFixed(1)}deg is larger than needed`)
          }
          // hit test: every chip centre (and its rim) resolves to itself; empty space does not
          for (let a = 0; a < cnt; a++) {
            ok(g.chipHit(s[a].r, s[a].ang, s, T.chipSize / 2 + 2) === a, `${tag} chipHit centre ${a}`)
            ok(g.chipHit(s[a].r + T.chipSize / 2 - 1, s[a].ang, s, T.chipSize / 2 + 2) === a, `${tag} chipHit rim ${a}`)
            ok(g.chipHit(s[a].r, s[a].ang, s, T.chipSize / 2 + 2, s.map((_, i) => i !== a)) !== a, `${tag} chipHit allowed mask ${a}`)
          }
          ok(g.chipHit(rc - T.chipSize - 10, mid, s, T.chipSize / 2 + 2) === -1, `${tag} chipHit inside petal area`)
        }
      }
    }
  }
  console.log(`chip arcs: ${nTot} layouts, ${nShift} shifted, ${nOff} still partly off screen (overflow counts at screen edges)`)
  // explicit: centre hub, 5 chips -> single arc centred on the petal, wider than the petal when many
  {
    const mid = -Math.PI / 2, rc = 110, s = g.chipSlots(5, mid, rc, 640, 400, W, H, T)
    ok(Math.abs(s.shift) < 1e-12 && s.every(c => c.row === 0), 'centre 5 chips single unshifted arc')
    ok(Math.abs(s[2].ang - mid) < 1e-9 && Math.abs(s[0].ang + s[4].ang - 2 * mid) < 1e-9, 'centre 5 chips symmetric')
    const m8 = g.chipSlots(9, mid, rc, 640, 400, W, H, T)
    ok(Math.max(...m8.map(c => c.row)) === 1 && m8.filter(c => c.row === 0).length === 8, 'overflow: 9 chips -> 8 on the arc + 1 on the next arc')
    // near the right edge the fan shifts toward the screen and stays on screen
    const e = g.chipSlots(5, 0, rc, 1270, 400, W, H, T)
    ok(e.shift !== 0 && e.every(c => 1270 + c.x <= W - margin + 1), 'right-edge fan shifts on screen')
    ok(Math.abs(g.wrap(e[2].ang - 0)) > 0.3, 'right-edge fan moved off the offscreen side')
  }
}

// ---- seam wedge paths ------------------------------------------------------------------------------
{
  const lay2 = g.layout(7, { full: true, start: -Math.PI / 2, span: 2 * Math.PI, dir: 1 }, T, 1)
  for (const p of lay2) {
    for (const roExtra of [0, 6]) {
      const d = g.seamPath(100, 100, p.ri, p.ro + roExtra, p.a0, p.a1, 8)
      ok(/^M[\d. -]+A/.test(d) && !/NaN/.test(d) && /Z$/.test(d), 'seamPath well formed ' + d.slice(0, 40))
    }
  }
  ok(g.seamPath(0, 0, 40, 41, 0, 1, 8) === '', 'seamPath degenerate -> empty')
  ok(g.seamPath(0, 0, 40, 90, 1, 1, 8) === '', 'seamPath zero span -> empty')
}

// ---- settings card placement ---------------------------------------------------------------------------
{
  const cw = [206, 240], ch = 76, GAP = 10, M = 12
  const spots2 = Object.assign({}, spots, { edgeTop: [640, 30], edgeLeft: [30, 400], edgeRight: [1250, 400], edgeBottom: [640, 770], nearTL: [60, 60], nearBR: [1220, 740] })
  const clampHub = (x, y) => [Math.max(28, Math.min(W - 28, x)), Math.max(28, Math.min(H - 28, y))]
  let n = 0, primary = 0, mirrored = 0, fanned = 0
  for (const w of cw) for (const [name, [x0, y0]] of Object.entries(spots2)) {
    const [hx, hy] = clampHub(x0, y0)
    for (const cnt of [6, 7, 8, 9]) {
      const arc = g.arcFor(hx, hy, W, H, cnt, T)
      const K = Math.max(1, Math.min(T.maxScale, cnt * T.minPetalAngle / arc.span))
      const mid = arc.start + arc.dir * (cnt - 0.5) * arc.span / cnt, R = T.outerR * K
      const p = g.cardPlace(hx, hy, R, mid, w, ch, GAP, W, H, M)
      const tag = `${name} n=${cnt} w=${w}`
      n++
      ok(p.x >= M - 1e-9 && p.y >= M - 1e-9 && p.x + w <= W - M + 1e-9 && p.y + ch <= H - M + 1e-9, `card on screen ${tag}`)
      ok(g.rectClearance(hx, hy, p.x, p.y, w, ch) >= R + T.hoverGrow, `card clear of ring incl. hover growth ${tag}`)
      ok(Math.abs(p.clear - g.rectClearance(hx, hy, p.x, p.y, w, ch)) < 1e-9, `clearance consistent ${tag}`)
      if (p.index === 0) {
        primary++
        // on the gear's outward axis when nothing had to slide it, else still hugging the ring (gap or more)
        ok(p.clear >= R + GAP - 1e-6, `primary keeps cardGap ${tag}`)
      } else if (p.index === 1) mirrored++; else fanned++
    }
  }
  // open centre: the card sits exactly cardGap beyond the gear petal's outer edge, centred on the axis
  { const [hx, hy] = [640, 400], arc = g.arcFor(hx, hy, W, H, 6, T), K = Math.max(1, Math.min(T.maxScale, 6 * T.minPetalAngle / arc.span))
    const mid = arc.start + arc.dir * 5.5 * arc.span / 6, R = T.outerR * K, w = 206
    const p = g.cardPlace(hx, hy, R, mid, w, ch, GAP, W, H, M)
    const clr = g.rectClearance(hx, hy, p.x, p.y, w, ch)
    ok(p.index === 0 && Math.abs(clr - (R + GAP)) < 1e-6, 'centre: gap to the gear petal = cardGap')
    ok(Math.abs((p.x + w / 2 - hx) * Math.sin(mid) - (p.y + ch / 2 - hy) * Math.cos(mid)) < 1e-6, 'centre: card centred on the gear axis') }
  console.log(`card placement: ${n} cases (${primary} on the gear axis, ${mirrored} mirrored, ${fanned} fanned)`)
}
console.log(`${checks} checks, ${fails} failures`); process.exit(fails ? 1 : 0)
