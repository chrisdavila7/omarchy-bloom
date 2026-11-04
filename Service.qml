import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons as Host
import "Geometry.js" as G
import "ColumnGeometry.js" as CG

// Bloom: a mouse-first workspace switcher grown from the cursor as one smoked-glass object.
// A hub, a continuous ring of wedge petals (workspaces) and, on hover, window chips on the petal's outer edge.
// A vertical layout (an Omarchy-style workspace column) is available as a global setting.
Item {
    id: root
    property var shell: null
    property var manifest: null

    // One petal's curved glass band: one band per chip arc, growing out of the petal spawn point with progress p
    // (same radial/angular/scale/fade mapping as the chips, so rail and chips move as one unit).
    // Faint grayscale app icon behind a workspace number. Two image slots crossfade when the source changes;
    // one MultiEffect on the whole item (cheap, no per-frame rebinding). Empty/unknown class -> nothing.
    component AppMark: Item {
        id: am
        property string cls: ""
        property real size: 40
        property real fadeMs: 180
        readonly property string src: {
            DesktopEntries.applications.values
            const e = cls ? DesktopEntries.heuristicLookup(cls) : null
            return e && e.icon ? Quickshell.iconPath(e.icon, true) : ""
        }
        property string srcA: ""
        property string srcB: ""
        property bool useA: true
        Component.onCompleted: srcA = src
        onSrcChanged: { if (useA) { srcB = src; useA = false } else { srcA = src; useA = true } }
        width: size; height: size
        visible: srcA !== "" || srcB !== ""
        layer.enabled: visible
        // grayscale + a radial feather: the icon's own tile (square / rounded square background) fades to nothing at its
        // edge, so the mark reads as a soft emblem on the glass rather than a tile
        layer.effect: MultiEffect { saturation: -1.0; maskEnabled: true; maskSource: featherMask; maskThresholdMin: 0.0; maskSpreadAtMin: 0.0 }
        Item {
            id: featherMask
            anchors.fill: parent; visible: false; layer.enabled: true
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: am.size / 2; centerY: am.size / 2; focalX: centerX; focalY: centerY
                        centerRadius: am.size / 2
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1) }
                        GradientStop { position: 0.34; color: Qt.rgba(1, 1, 1, 1) }
                        GradientStop { position: 0.46; color: Qt.rgba(1, 1, 1, 0.70) }
                        GradientStop { position: 0.56; color: Qt.rgba(1, 1, 1, 0.32) }
                        GradientStop { position: 0.64; color: Qt.rgba(1, 1, 1, 0.10) }
                        GradientStop { position: 0.72; color: Qt.rgba(1, 1, 1, 0) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                    }
                    PathSvg { path: "M0 0 H" + am.size + " V" + am.size + " H0 Z" }
                }
            }
        }
        Image {
            anchors.fill: parent; fillMode: Image.PreserveAspectFit; smooth: true; asynchronous: true
            sourceSize: Qt.size(am.size * 2, am.size * 2); source: am.srcA
            opacity: am.useA && am.srcA !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.dur(am.fadeMs); easing.type: Easing.OutCubic } }
        }
        Image {
            anchors.fill: parent; fillMode: Image.PreserveAspectFit; smooth: true; asynchronous: true
            sourceSize: Qt.size(am.size * 2, am.size * 2); source: am.srcB
            opacity: !am.useA && am.srcB !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.dur(am.fadeMs); easing.type: Easing.OutCubic } }
        }
    }

    component RailArc: Item {
        id: ra
        property var th: null
        property var rows: []            // [{r, a0, a1}] in bloom-local polar coords
        property real spawnA: 0
        property real spawnR: 0
        property real p: 1
        property bool live: false        // current-petal rail: rows follow window changes (smoothly)
        anchors.fill: parent
        Repeater {
            model: ra.th ? ra.th.railMaxRows : 0
            delegate: Shape {
                id: rs
                required property int index
                readonly property var row: ra.rows[index]
                property var last: null
                onRowChanged: if (row) last = row
                property bool armed: false
                onLastChanged: if (last) Qt.callLater(() => { rs.armed = true })
                property real ta0: last ? last.a0 : 0
                property real ta1: last ? last.a1 : 0
                property real tr: last ? last.r : 0
                property real a0: ta0
                property real a1: ta1
                property real rr: tr
                Behavior on a0 { enabled: ra.live && rs.armed; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                Behavior on a1 { enabled: ra.live && rs.armed; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                Behavior on rr { enabled: ra.live && rs.armed; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                property real rowK: row ? 1 : 0           // a row the petal no longer needs fades on its own
                Behavior on rowK { NumberAnimation { duration: root.fdur(ra.th ? ra.th.chipFallMs : 120); easing.type: Easing.InCubic } }
                readonly property real pp: Math.max(0, Math.min(1, ra.p))
                readonly property real sc: ra.th ? ra.th.chipSpawnScale + (1 - ra.th.chipSpawnScale) * pp : 1
                readonly property real b: ra.th ? ra.th.boundary : 0
                readonly property real cr: ra.spawnR + (rr - ra.spawnR) * pp
                readonly property real c0: ra.spawnA + G.wrap(a0 - ra.spawnA) * pp
                readonly property real c1: ra.spawnA + G.wrap(a1 - ra.spawnA) * pp
                visible: !!last && pp > 0.004
                x: -b; y: -b; width: b * 2; height: b * 2
                preferredRendererType: Shape.CurveRenderer
                opacity: pp * rowK
                ShapePath {
                    strokeWidth: ra.th ? (ra.th.railWidth + 2) * rs.sc : 0; strokeColor: Qt.rgba(1, 1, 1, 0.20)
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathSvg { path: rs.last ? G.arcPath(rs.b, rs.b, rs.cr, rs.c0 - 0.02, rs.c1 + 0.02) : "" }
                }
                ShapePath {
                    strokeWidth: ra.th ? ra.th.railWidth * rs.sc : 0
                    strokeColor: ra.th ? Qt.rgba(ra.th.glass.r, ra.th.glass.g, ra.th.glass.b, 0.66) : "transparent"
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathSvg { path: rs.last ? G.arcPath(rs.b, rs.b, rs.cr, rs.c0 - 0.02, rs.c1 + 0.02) : "" }
                }
            }
        }
    }

    // Vertical layout's chip band: one rounded glass bar per chip row, growing out of the slot's spawn point
    // with progress p (same rise mapping as the chips: positions interpolate from the spawn point, scale and fade).
    component RailRect: Item {
        id: rr
        property var th: null
        property var rows: []            // [{y, x0, x1}] in column-local coords
        property real spawnX: 0
        property real spawnY: 0
        property real p: 1
        property bool live: false
        anchors.fill: parent
        Repeater {
            model: rr.th ? rr.th.railMaxRows : 0
            delegate: Rectangle {
                id: rb
                required property int index
                readonly property var row: rr.rows[index]
                property var last: null
                onRowChanged: if (row) last = row
                property bool armed: false
                onLastChanged: if (last) Qt.callLater(() => { rb.armed = true })
                property real ty: last ? last.y : 0
                property real tx0: last ? last.x0 : 0
                property real tx1: last ? last.x1 : 0
                property real yy: ty
                property real xa: tx0
                property real xb: tx1
                Behavior on yy { enabled: rr.live && rb.armed; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                Behavior on xa { enabled: rr.live && rb.armed; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                Behavior on xb { enabled: rr.live && rb.armed; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                property real rowK: row ? 1 : 0
                Behavior on rowK { NumberAnimation { duration: root.fdur(rr.th ? rr.th.chipFallMs : 120); easing.type: Easing.InCubic } }
                readonly property real pp: Math.max(0, Math.min(1, rr.p))
                readonly property real sc: rr.th ? rr.th.chipSpawnScale + (1 - rr.th.chipSpawnScale) * pp : 1
                readonly property real cy: rr.spawnY + (yy - rr.spawnY) * pp
                readonly property real cxa: rr.spawnX + (xa - rr.spawnX) * pp
                readonly property real cxb: rr.spawnX + (xb - rr.spawnX) * pp
                readonly property real hh: rr.th ? rr.th.railWidth * sc : 0
                visible: !!last && pp > 0.004
                x: Math.min(cxa, cxb); width: Math.abs(cxb - cxa)
                y: cy - hh / 2; height: hh
                radius: hh / 2
                opacity: pp * rowK
                color: rr.th ? Qt.rgba(rr.th.glass.r, rr.th.glass.g, rr.th.glass.b, 0.66) : "transparent"
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20)
            }
        }
    }

    // ------------------------------------------------------------------ theme
    // Every size, colour and duration lives here.
    readonly property QtObject theme: QtObject {
        // geometry (logical px)
        // Reduced motion: Omarchy's own switch (Host.Style.reduceMotion = Hyprland animations off). Every animation
        // duration goes through root.dur() (0 when reduced); open/close become one short fade, with no unfold stagger,
        // overshoot or pointer drift.
        readonly property bool reduced: Host.Style.reduceMotion === true
        readonly property int reducedFadeMs: 80
        readonly property int reducedChipMs: 90   // chips / bands / settings card fade in reduced motion
        readonly property real hubR: 22
        readonly property real innerR: 40
        readonly property real outerR: 92
        readonly property real hoverGrow: 6        // hovered petal grows this far outward (bloom) / hovered slot widens this much toward the screen centre (vertical)
        readonly property real hitSlop: 4
        readonly property real gap: 2              // hairline between petals
        readonly property real corner: 7
        readonly property real minPetalAngle: 0.42
        readonly property real maxScale: 1.7       // ring grows only when very many workspaces would make the petals too narrow
        readonly property real edgeMargin: 8
        // recessed well (visual only; hit-testing uses hubR / aimDeadZone). Its radius is the petals' inner
        // radius (innerR * ring scale) minus wellGap, so it keeps the same hairline from the petals at any scale.
        readonly property real wellGap: 2          // px between the well rim and the petals' inner edge (= gap)
        readonly property real wellFillAlpha: 0.22 // faint fill; kept above the blur ignore_alpha (0.2) so the well frosts like the glass
        readonly property color wellFillColor: "#7a7a7a" // lighter than the smoked glass: the well reads airy/emptier than the petals, the inner shadow keeps it recessed
        // glass seams: the hairline gaps (2 px) are filled with this near-black so they are blurred (alpha > ignore_alpha) and
        // read as deliberate glass seams over any wallpaper, instead of bright unblurred cracks
        readonly property real seamAlpha: 0.32
        readonly property real seamBleed: 0.4      // px the seam wedge overlaps the petal's arcs, so even-odd edges never coincide (no dotted fringe)
        readonly property real wellShadowAlpha: 0.20 // inner shadow darkness at the very upper rim
        readonly property real wellShadowStart: 0.74 // radial position where the shadow begins (0..1): a thin crescent at the upper rim, fading quickly
        readonly property real wellShadowOffsetK: 0.16 // shadow gradient centre sits this fraction of the well radius below the centre (light from above)
        readonly property real wellLipAlpha: 0.07  // faint light lip on the lower inner rim
        readonly property real chipSize: 34
        readonly property real chipEdgeGap: 7      // px from the grown petal's outer edge to the chips' inner edge
        readonly property real chipGap: 6          // px between neighbouring chips on the arc (pitch = chipSize + chipGap)
        readonly property real chipMaxSpanDeg: 150 // widest fan of one arc; more chips overflow onto the next arc outward
        readonly property real chipRowStep: 44     // radial step of overflow arcs
        readonly property real railWidth: chipSize + 6 // curved glass band thickness
        readonly property real driftMax: reduced ? 0 : 3
        readonly property real driftGain: 0.04
        readonly property real driftSpring: 0.4    // heavy, slow follow
        readonly property real driftDamping: 0.4
        readonly property real boundary: 300       // half-size of per-petal shape canvas
        readonly property int dragThreshold: 6
        readonly property real ghostLift: 46
        // Colours. matchTheme: true = accent is the live Omarchy accent (Host.Color.accent) lifted to
        // HSL lightness >= 0.62, saturation <= 0.65 for legibility, and the glass base blends 10% of it;
        // false = neutral accent #e4e8ed and plain #343434 glass.
        // Driven by the Theme setting (root.themeMode); this is the default used before settings load.
        readonly property bool matchTheme: root.themeMode === "omarchy"
        readonly property color themeAccent: Host.Color.accent || "#7daea3"
        readonly property color themeAccentLegible: Qt.hsla(Math.max(0, themeAccent.hslHue), Math.min(themeAccent.hslSaturation, 0.65), Math.max(themeAccent.hslLightness, 0.62), 1)
        readonly property color neutralAccent: "#e4e8ed"
        // accent + glass crossfade when the Theme setting flips
        property color accent: matchTheme ? themeAccentLegible : neutralAccent
        Behavior on accent { ColorAnimation { duration: root.dur(root.theme.themeMs); easing.type: Easing.OutCubic } }
        readonly property color text: "#e4e8ed"
        // smoked-glass base: dark enough to read as glass, light enough to stay legible in both themes
        readonly property color glassBase: "#343434"
        readonly property real glassTintMix: 0.10
        property color glass: matchTheme
            ? Qt.rgba(glassBase.r + (themeAccentLegible.r - glassBase.r) * glassTintMix, glassBase.g + (themeAccentLegible.g - glassBase.g) * glassTintMix, glassBase.b + (themeAccentLegible.b - glassBase.b) * glassTintMix, 1)
            : glassBase
        Behavior on glass { ColorAnimation { duration: root.dur(root.theme.themeMs); easing.type: Easing.OutCubic } }
        readonly property int themeMs: 180         // Theme setting colour crossfade, OutCubic
        readonly property color errorText: "#e08a84"   // error red (reserved; no error toast yet)
        readonly property real glassOccupied: 0.66
        readonly property real glassEmpty: 0.50
        readonly property real glassHover: 0.74
        // depth light: smooth overlay on each petal/slot glass; lighter toward the outer edge, darker toward the well
        // (vertical: lighter on the centre-facing side, where the rim catch and chips live; darker on the screen side)
        readonly property real depthLightTop: 0.05    // white alpha at the outer edge
        readonly property real depthShadeInner: 0.07  // black alpha at the inner edge
        // app watermark: the workspace's main app icon, grayscale, behind the number
        readonly property real watermarkAlpha: 0.07
        readonly property real watermarkHoverAdd: 0.02
        readonly property real watermarkScale: 0.75   // bloom: icon size as a fraction of the petal's radial depth
        readonly property real colWatermarkPx: 28     // vertical: icon size
        readonly property int watermarkFadeMs: 180    // crossfade when the main app changes
        readonly property int settingsGlyphPx: 17     // bloom Settings petal glyph
        readonly property real gearFallbackScale: 1.7 // the plain U+2699 gear is ~60% of the cog's visual size
        readonly property real hoverLift: 0.11     // lightening of the glass tint on hover
        // hover = rim catch: white light on the outer edge, centred on the pointer angle
        readonly property real rimCatchWidth: 2.4   // px, thickness of the lit arc
        readonly property real rimCatchInset: 0.6   // px, gap between the lit arc and the outer edge
        readonly property real rimCatchAlpha: 0.70  // peak white alpha
        readonly property real rimCatchSpread: 0.40 // falloff reach each side, fraction of the petal angular width
        readonly property int rimCatchInMs: 120     // OutCubic
        readonly property int rimCatchOutMs: 120    // InCubic
        // current workspace = accent tick at the middle of the outer edge
        readonly property real tickLen: 11          // px along the arc
        readonly property real tickWidth: 2.5
        readonly property real tickInset: 6.0       // px inside the outer edge (to the tick's centre line); clear of the rim catch (0.6 + 2.4 px)
        readonly property real tickAlpha: 0.95
        readonly property real membraneAlpha: 0.34
        readonly property real chipAlpha: 0.84
        readonly property color edgeLight: Qt.rgba(1, 1, 1, 0.26)
        readonly property color topLight: Qt.rgba(1, 1, 1, 0.13)
        readonly property real vignetteMax: 0.175
        readonly property real vignetteClear: 0.45 // clear fraction of the radial falloff around the bloom
        readonly property real chipSpawnInset: 10  // chips spawn this far inside the petal's outer edge
        readonly property real chipSpawnScale: 0.85 // chip scale at the spawn point
        readonly property real chipHitRise: 0.7    // chip is hittable once this far out (0..1)
        // type
        // Inter (assets/fonts/Inter-Variable.ttf, SIL OFL 1.1; see assets/fonts/INTER-OFL.txt)
        readonly property string font: interFont.status === FontLoader.Ready ? interFont.name : "Inter"
        readonly property int numberPx: 15
        readonly property int labelPx: 11
        // motion (ms)
        readonly property real overshoot: 1.2      // easeOutBack s ~ 1.05 peak
        readonly property int petalMs: reduced ? reducedFadeMs : 120
        readonly property int stagger: reduced ? 0 : 12
        readonly property int closeMs: reduced ? reducedFadeMs : 120
        readonly property int hoverMs: 100
        readonly property int pressMs: 70
        readonly property int aimMs: 160
        readonly property real aimDeadZone: 22     // px: aim angle holds inside this radius (= hubR)
        readonly property real aimDeadHyst: 4      // px: leave the dead zone beyond aimDeadZone + this
        readonly property real aimMaxDegPerSec: 540 // ring angular speed cap
        readonly property real aimEaseRate: 12     // 1/s: gentle exponential ease for small deltas
        readonly property int driftMs: 150
        readonly property int revealMs: 150
        readonly property int hideMs: 250
        readonly property int chipRiseMs: 140        // spawn out of the petal (OutCubic)
        readonly property int chipFallMs: 120        // retract into the petal (InCubic = mirrored curve)
        readonly property int railMaxRows: 6   // overflow arcs that get a glass band
        readonly property int pulseMs: 220
        readonly property int pulseHoldMs: 450
        readonly property int flyMs: 260
        readonly property int toastMs: 2400
        readonly property int doneCloseMs: 310
        readonly property int reconcileMs: 700
        // ---- vertical layout (workspace column, after Omarchy's native Workspaces widget)
        readonly property real slotSize: 40        // slot is a square this big
        readonly property real slotGap: 3          // spacing between slot cells (pitch = slotSize + slotGap)
        readonly property real slotHair: 2         // drawn hairline between neighbouring slots (<= slotGap)
        readonly property real separator: 8        // gap before the guest group and before Settings
        readonly property real colRadius: 12       // outer corners of each group
        readonly property real colInnerRadius: 3   // corners between neighbouring slots
        readonly property real colOvershoot: 0.5   // restrained easeOutBack (bloom: overshoot)
        readonly property int colStagger: reduced ? 0 : 14       // ms per slot away from the current one
        readonly property int colNumberPx: 17
        readonly property int colGearPx: 18           // vertical Settings gear
        readonly property int colGlyphPx: 10          // current slot's layout glyph (badge): ~60% of the numeral cap height once drawn
        readonly property real colGlyphAlpha: 0.85
        readonly property int colPairNumberPx: 14     // number under the badge
        readonly property real colPairNumberDy: 6     // px the number moves down / the badge moves up (40 px slot)
        readonly property real colBadgeDy: -9
        readonly property real colPress: 0.97      // label scale while pressed
        readonly property int colPressMs: 160
        readonly property int colEmptyMs: 140      // empty slots (opacity 0.5) fade over this
        readonly property real colEmptyAlpha: 0.5
        readonly property real colTickInset: 6.0
        readonly property real chipRowPitch: 42    // vertical step of wrapped chip rows
        readonly property int chipMaxCols: 8       // widest chip row
        readonly property real bandPad: 3          // glass band overhang beyond the outer chips
        // icon font + layout glyphs (Nerd Font code points); family = the shell's Style.fontFamily (fontconfig "monospace")
        readonly property string iconFont: root.glyphFamily
        readonly property string glyphDwindle: "\u{f14fb}"
        readonly property string glyphScrolling: "\u{f0765}"
        readonly property string glyphFloating: "\u{f0536}"
        readonly property string glyphGear: "\u{f0493}"   // nf-md-cog
        // ---- settings card
        readonly property real cardRow: 28
        readonly property real cardPad: 8
        readonly property real cardRowGap: 4       // between settings rows
        readonly property real cardRadius: 12
        readonly property real cardGap: 10         // gap between the Settings item (petal outer edge / slot edge) and the card
        readonly property real cardMargin: 12      // card stays this far inside the screen
        readonly property real cardAlpha: 0.86
        readonly property real cardScale0: 0.96    // scale it grows from
        readonly property int cardInMs: 160        // OutCubic
        readonly property int cardOutMs: 120       // InCubic
        readonly property int cardLabelPx: 13
        readonly property int segPx: 12
        readonly property real segW: 66            // width of one segment
        readonly property int segMs: 180           // selection pill slide, OutCubic
        readonly property real pillAlpha: 0.14     // white selection pill
        // ---- layout morph (no overshoot)
        readonly property int morphMs: 240         // OutCubic
        readonly property real morphScale: 0.85    // shapes shrink to / grow from this scale while crossfading
        readonly property int eventDebounceMs: 40  // coalesce Hyprland events before refreshing
        readonly property int settleMs: 90         // wait after a refresh before rebuilding the model
        readonly property int refreshMs: 260       // re-read toplevels after a move
        readonly property int settingsDebounceMs: 150 // coalesce rapid settings changes into one write
        readonly property int morphWaitMs: 170     // chips + bands retract first (chipFallMs + margin)
    }
    readonly property QtObject th: theme
    FontLoader { id: interFont; source: Qt.resolvedUrl("assets/fonts/Inter-Variable.ttf") }

    // ---- glyph font. Omarchy's bar draws the layout glyphs (U+F14FB / U+F0765 / U+F0536) and Bloom the gear (U+F0493) in
    // Style.fontFamily, the fontconfig "monospace" alias, which only reaches a Nerd Font through fallback. Bloom asks
    // fontconfig once which installed families really contain all four code points and draws them in that family
    // (the shell's own family first when it qualifies). If none qualifies (no Nerd Font installed) the current slot
    // shows its number plus the accent tick, and the gear a plain symbol, instead of a missing-glyph box.
    property string glyphFamily: Host.Style.fontFamily || "monospace"
    property bool glyphOk: true            // stays true until fontconfig answered with an empty list
    function pickGlyphFont(text) {
        const fams = String(text || "").split("\n").map(x => x.trim()).filter(x => x.length > 0)
        if (fams.length === 0) { glyphOk = false; return }
        const own = [Host.Style.fontFamily, Host.Style.resolvedFontFamily]
        let pick = fams.find(f => own.includes(f)) || fams.find(f => /nerd/i.test(f)) || fams[0]
        glyphFamily = pick; glyphOk = true
    }
    Connections { target: Host.Style; function onResolvedFontFamilyChanged() { glyphProc.running = true } }
    Process {
        id: glyphProc
        command: ["fc-list", "-f", "%{family[0]}\\n", ":charset=f14fb f0765 f0536 f0493"]
        stdout: StdioCollector { id: glyphOut }
        onExited: function (code) { if (code === 0) root.pickGlyphFont(glyphOut.text) }
    }

    // ------------------------------------------------------------ layout setting
    // Settings, persisted in ~/.local/state/bloom/settings.json as {"layout": "bloom"|"vertical", "theme": "neutral"|"omarchy"}.
    // layoutMode = the setting; lm = the layout the open switcher is showing (follows layoutMode when the
    // switcher is closed, or through the morph while it is open).
    readonly property string settingsDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/bloom"
    readonly property string settingsPath: settingsDir + "/settings.json"
    property string layoutMode: "bloom"
    // Theme setting: "omarchy" (default, matchTheme on) | "neutral"; settings.json key "theme"
    property string themeMode: "omarchy"
    function validTheme(n) { return n === "neutral" || n === "omarchy" }
    function setTheme(name) {
        if (!validTheme(name)) return false
        if (name !== themeMode) { themeMode = name; persistSettings() }
        return true
    }
    property string lm: "bloom"
    readonly property bool vert: lm === "vertical"
    function validLayout(n) { return n === "bloom" || n === "vertical" }
    function setLayout(name) {
        if (!validLayout(name)) return false
        const changed = name !== layoutMode
        layoutMode = name
        if (changed) persistSettings()
        if (shown && active) requestMorph(); else applyLayout()
        return true
    }
    function applyLayout() { if (!shown) { lm = layoutMode; vK = vert ? 1 : 0 } }
    // ---- morph: vK = how vertical the drawn switcher is (0 bloom .. 1 vertical), animated; lm flips at the start
    property real vK: 0
    property bool morphing: false
    NumberAnimation { id: morphAnim; target: root; property: "vK"; duration: root.dur(root.th.morphMs); easing.type: Easing.OutCubic
        onFinished: { root.morphing = false; if (root.shown && root.active && root.lm !== root.layoutMode) root.requestMorph() } }
    Timer { id: morphTimer; interval: th.morphWaitMs; onTriggered: root.startMorph() }
    function requestMorph() {
        if (!shown || !active || lm === layoutMode || morphing || morphTimer.running) return
        // chips and bands retract into their slot / petal first, then everything moves
        hovered = -1; pressedIdx = -1
        revealTimer.stop(); hideTimer.stop()
        const wait = chipList.count > 0 || leaveList.count > 0
        if (revealed >= 0) { if (chipList.count > 0) setReveal(-1); else applyReveal(-1) }
        morphing = true
        if (wait) morphTimer.restart(); else startMorph()
    }
    function startMorph() {
        if (!shown || !active) { morphing = false; return }
        if (revealed >= 0 || chipList.count > 0) { swapTimer.stop(); applyReveal(-1) }
        lm = layoutMode
        clockAnim.stop(); clock = clockTotal
        rimY = py
        morphAnim.stop(); morphAnim.from = vK; morphAnim.to = vert ? 1 : 0; morphAnim.start()
    }
    function persistSettings() { settingsTimer.restart() }
    Timer { id: settingsTimer; interval: th.settingsDebounceMs; onTriggered: root.writeSettings() }
    function writeSettings() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$3.tmp" && mv "$3.tmp" "$3"', "sh", settingsDir, JSON.stringify({ layout: layoutMode, theme: themeMode }), settingsPath])
    }
    FileView {
        id: settingsFile
        path: root.settingsPath
        printErrors: false
        onLoaded: {
            try { const o = JSON.parse(text()); if (root.validTheme(o.theme)) root.themeMode = o.theme; if (root.validLayout(o.layout)) { root.layoutMode = o.layout; root.applyLayout() } } catch (e) { console.warn("Bloom: settings.json: " + e) }
        }
    }
    Component.onCompleted: { Quickshell.execDetached(["mkdir", "-p", root.settingsDir]); glyphProc.running = true }
    Component.onDestruction: if (settingsTimer.running) { settingsTimer.stop(); writeSettings() }

    // ------------------------------------------------------------------ state
    readonly property int persistentWorkspaces: 5
    readonly property string backend: decodeURIComponent(String(Qt.resolvedUrl("backend.py")).replace(/^file:\/\//, ""))
    property bool shown: false           // panels mapped
    property bool active: false          // open target (false while folding)
    property bool pending: false
    property real clock: 0               // animation clock in ms; drives every unfold
    readonly property real clockTotal: th.reduced ? th.reducedFadeMs : vert ? Math.max(colDistance(0), colDistance(itemCount - 1)) * th.colStagger + th.petalMs : (count - 1) * th.stagger + th.petalMs
    property var targetScreen: null
    property string monitorName: ""
    // curX/curY = the pointer at open (kept 28 px from the edge). The vertical layout is centred on it; the bloom's hub (bhx/bhy)
    // is that point clamped inward so the whole ring incl. hover growth stays on screen. hx/hy = the hub of what is drawn now
    // (they glide between the two during a layout morph).
    property real curX: 0
    property real curY: 0
    readonly property var bloomHub: G.hubClamp(curX, curY, G.ringExtent(count, th), sw, sh, th.edgeMargin)
    readonly property real bhx: bloomHub.x
    readonly property real bhy: bloomHub.y
    readonly property real hx: curX + (bhx - curX) * (1 - vK)
    readonly property real hy: curY + (bhy - curY) * (1 - vK)
    property real sw: 1280
    property real sh: 800
    property real driftX: 0
    property real driftY: 0
    property real px: 0
    property real py: 0
    property bool inputReady: false

    property var frozen: []
    property var wsApp: ({})              // workspace id -> class of its main app
    property string wsAppSig: ""
    property int currentWs: 1
    property var windows: []             // [{address,ws,title,cls,floating,fullscreen,grouped}]
    property var modes: ({})
    property var usedIds: []
    property var overrides: ({})         // optimistic moves: address -> {ws, until}
    readonly property int count: frozen.length + 1

    property int hovered: -1
    property int revealed: -1
    property int pressedIdx: -1
    property int pulse: -1
    property bool chipsOpen: false
    property int hoverChip: -1
    property real aimRaw: -Math.PI / 2
    property real aimAngle: -Math.PI / 2
    property bool aimHold: false
    // frame-driven: shortest-path approach to aimRaw, speed-capped, no overshoot; runs only while open and off-target
    FrameAnimation {
        running: root.shown && Math.abs(G.wrap(root.aimRaw - root.aimAngle)) > 0.0005
        onTriggered: {
            if (root.th.reduced) { root.aimAngle = root.aimRaw; return }
            const d = G.wrap(root.aimRaw - root.aimAngle)
            const dt = Math.min(frameTime, 0.05)
            const maxStep = root.th.aimMaxDegPerSec * Math.PI / 180 * dt
            const step = Math.min(Math.abs(d), maxStep, Math.abs(d) * (1 - Math.exp(-root.th.aimEaseRate * dt)) + 0.0005)
            root.aimAngle += (d < 0 ? -step : step)
        }
    }
    Behavior on driftX { SpringAnimation { spring: th.driftSpring; damping: th.driftDamping; epsilon: 0.05 } }
    Behavior on driftY { SpringAnimation { spring: th.driftSpring; damping: th.driftDamping; epsilon: 0.05 } }

    // drag
    property string dragAddr: ""
    property var dragWin: null
    property int dragSrcWs: -1
    property int dragSrcSlot: -1
    property int dragSrcPetal: -1
    property real downX: 0
    property real downY: 0
    property bool dragging: false
    property bool flying: false
    property real gx: 0
    property real gy: 0
    property int insIdx: -1
    property string insSide: ""
    property real fadeGhost: 1

    // toast
    property string toastText: ""
    property bool toastShown: false

    // ------------------------------------------------------------- geometry
    // always a complete ring at a fixed orientation (workspace 1 at 12 o'clock, Settings last): it never rotates
    readonly property var arc: G.fullArc()
    readonly property real ringK: G.ringScale(count, th)
    readonly property var lay: G.layout(count, arc, th, ringK)
    // vertical layout: items = workspaces, then Settings. The full rail is centered at open.
    property int anchorIdx: 0
    readonly property int itemCount: frozen.length + 1
    readonly property int settingsIndex: frozen.length
    function blockOf(id) { return Math.floor((id - 1) / 10) }
    function wsLabel(id) { const s = (id - 1) % 10 + 1; return s === 10 ? "0" : String(s) }
    readonly property var colBreaks: {
        const b = []
        for (let i = 1; i < frozen.length; i++) if (blockOf(frozen[i]) !== blockOf(frozen[0]) && blockOf(frozen[i - 1]) === blockOf(frozen[0])) { b.push(i); break }
        b.push(frozen.length)       // separator before Settings
        return b
    }
    readonly property var colLay: CG.column(hx, hy, itemCount, anchorIdx, sw, sh, th, colBreaks)
    property real rimY: 0               // smoothed pointer y driving the vertical rim catch
    Behavior on rimY { NumberAnimation { duration: root.dur(th.aimMs); easing.type: Easing.OutCubic } }
    readonly property real vigX: hx + (colLay.x + colLay.width / 2 - hx) * vK
    readonly property real vigY: hy + (colLay.y + colLay.height / 2 - hy) * vK
    // layout glyph of the current workspace, read natively (files under ~/.local/state/omarchy/workspace-layouts)
    readonly property string omarchyState: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/workspace-layouts"
    property string wsFileMode: ""
    property string defFileMode: ""
    property bool defFileExists: false
    readonly property string activeMode: wsFileMode || (defFileExists ? defFileMode : "") || modes[String(currentWs)] || "dwindle"
    function modeGlyph(m) { return m === "scrolling" ? th.glyphScrolling : (m === "floating" ? th.glyphFloating : th.glyphDwindle) }
    FileView {
        id: wsModeFile
        path: root.omarchyState + "/" + root.currentWs + ".lua"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { const m = /mode = "([a-z]*)"/.exec(text()); root.wsFileMode = m ? m[1] : "" }
        onLoadFailed: root.wsFileMode = ""
    }
    FileView {
        id: defModeFile
        path: root.omarchyState + "/default.lua"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { const m = /default = "([a-z]*)"/.exec(text()); root.defFileMode = m ? m[1] : ""; root.defFileExists = true }
        onLoadFailed: { root.defFileMode = ""; root.defFileExists = false }
    }
    function reloadModes() { wsModeFile.reload(); defModeFile.reload() }
    // reduced motion: the unfold collapses to one short fade (prog stays 1, opacity follows the clock)
    // the plain-symbol fallback gear (no Nerd Font installed) is a small glyph in text fonts: draw it larger so it matches the cog's visual size
    function gearPx(px) { return glyphOk ? px : Math.round(px * th.gearFallbackScale) }
    function dur(ms) { return th.reduced ? 0 : ms }
    // reduced motion keeps a short fade (th.reducedChipMs) for things that appear / disappear (chips, bands, settings card) instead of popping
    function fdur(ms) { return th.reduced ? th.reducedChipMs : ms }
    function openFade(prog, k) { return th.reduced ? Math.max(0, Math.min(1, clock / Math.max(1, clockTotal))) : Math.max(0, Math.min(1, prog * k)) }
    function easeOutBack(t, ov) { const s = ov === undefined ? th.overshoot : ov; t = t - 1; return 1 + (s + 1) * t * t * t + s * t * t }
    function colDistance(i) {
        const c = CG.itemCenter(colLay, i)
        return c ? Math.abs(c.y - (colLay.y + colLay.height / 2)) / (th.slotSize + th.slotGap) : 0
    }
    function petalProg(i, clk) {
        if (th.reduced) return 1
        if (vert) {   // column: slots unfold outward from the rail center
            const tv = Math.max(0, Math.min(1, (clk - colDistance(i) * th.colStagger) / th.petalMs))
            return active ? easeOutBack(tv, th.colOvershoot) : tv * tv * (3 - 2 * tv)
        }
        const t = Math.max(0, Math.min(1, (clk - i * th.stagger) / th.petalMs))
        return active ? easeOutBack(t) : t * t * (3 - 2 * t)
    }
    function baseMid(i) { const b = arc.span / count; return arc.start + arc.dir * (i + 0.5) * b }
    function wsAt(i) { return i === frozen.length ? -1 : frozen[i] }   // the last item is Settings (no workspace)
    function winCount(id) { let n = 0; for (const w of windows) if (w.ws === id) n++; return n }
    function winsOf(id) { return windows.filter(w => w.ws === id) }

    // Slots of the revealed petal's chips: stable (fully grown radius, base mid angle)
    // Chip arc: concentric with the dial, chipEdgeGap beyond the hovered petal's grown edge to the chip's inner edge
    readonly property real chipR0: th.outerR * ringK + th.hoverGrow + th.chipEdgeGap + th.chipSize / 2
    readonly property var slots: revealed < 0 ? [] : (vert ? CG.chipSlots(colLay, revealed, chipList.count, sw, sh, th) : G.chipSlots(chipList.count, baseMid(revealed), chipR0, hx, hy, sw, sh, th))
    readonly property var vRows: vert && slots.rows ? slots.rows : []
    readonly property var vSpawn: vert && revealed >= 0 && revealed < itemCount ? CG.spawnPoint(colLay, revealed, th) : null
    readonly property var railRows: {
        const out = []
        for (const s of slots) {
            let r = out[s.row]
            if (!r) { r = { r: s.r, a0: s.ang, a1: s.ang }; out[s.row] = r }
            r.a0 = Math.min(r.a0, s.ang); r.a1 = Math.max(r.a1, s.ang)
        }
        return out
    }

    function chipPanel(j) {
        const s = slots[j]
        if (!s) return Qt.point(-999, -999)
        const bx = vert ? driftX : hx + driftX, by = vert ? driftY : hy + driftY
        return Qt.point(Math.max(8 + th.chipSize / 2, Math.min(sw - 8 - th.chipSize / 2, bx + s.x)),
                        Math.max(8 + th.chipSize / 2, Math.min(sh - 8 - th.chipSize / 2, by + s.y)))
    }
    function chipAt(x, y) {
        if (!chipsOpen || revealed < 0) return -1
        const cx = hx + driftX, cy = hy + driftY
        const ok = []
        for (let j = 0; j < slots.length; j++) {
            const it = chipRepeater.itemAt(j)
            ok.push(!!it && it.rise >= th.chipHitRise)
        }
        if (vert) return CG.chipHit(x - driftX, y - driftY, slots, th.chipSize / 2 + 2, ok)
        return G.chipHit(Math.hypot(x - cx, y - cy), Math.atan2(y - cy, x - cx), slots, th.chipSize / 2 + 2, ok)
    }
    function hitPetal(r, ang) {
        if (r < th.innerR * ringK - th.hitSlop) return -1
        const i = G.petalAt(r, ang, count, arc, th, ringK)
        if (i >= 0 && lay[i] && r > lay[i].ro + (i === hovered ? th.hoverGrow : 0)) return -1
        return i
    }
    // ---- layout interface (per layout: Geometry.js = bloom, ColumnGeometry.js = vertical) ----
    // itemHit(x, y)        item under the pointer or -1
    // landingPoint(i)      where a window dropped on item i vanishes into
    // inRevealRegion(x, y) pointer is on the open chip band / the corridor to it
    // slots / chipPanel(j) / chipAt(x, y)  chip slots of the revealed item and their hit test
    function itemHit(x, y) {
        if (vert) return CG.hitTest(colLay, x - driftX, y - driftY, hovered, th)
        const cx = hx + driftX, cy = hy + driftY
        return hitPetal(Math.hypot(x - cx, y - cy), Math.atan2(y - cy, x - cx))
    }
    function landingPoint(i) {
        if (vert) { const c = CG.itemCenter(colLay, i); return c ? Qt.point(c.x + driftX, c.y + driftY) : Qt.point(hx, hy) }
        const p = G.landingPoint(hx + driftX, hy + driftY, lay, i)
        return p ? Qt.point(p[0], p[1]) : Qt.point(hx + driftX, hy + driftY)
    }
    function inRevealRegion(x, y) {
        if (vert) return revealed >= 0 && chipsOpen && vRows.length > 0 && CG.inReveal(colLay, revealed, slots, x - driftX, y - driftY, 10, th)
        const cx = hx + driftX, cy = hy + driftY
        const r = Math.hypot(x - cx, y - cy), ang = Math.atan2(y - cy, x - cx)
        if (revealed < 0 || !chipsOpen || railRows.length === 0) return false
        const mid = baseMid(revealed)
        const half = lay[revealed] ? (lay[revealed].a1 - lay[revealed].a0) / 2 : 0.3
        if (r >= th.innerR * ringK && r <= chipR0 - th.chipSize && Math.abs(G.wrap(ang - mid)) <= half + 0.12) return true
        for (const row of railRows) {
            if (!row) continue
            const c = (row.a0 + row.a1) / 2, ext = (row.a1 - row.a0) / 2 + 26 / row.r
            if (Math.abs(r - row.r) <= th.railWidth / 2 + 10 && Math.abs(G.wrap(ang - c)) <= ext) return true
        }
        return false
    }

    // ---------------------------------------------------------- Hyprland data
    function currentOf(mon) {
        return mon && mon.activeWorkspace ? mon.activeWorkspace.id : currentWs
    }
    property string windowSig: ""
    function rebuild() {
        const mon = Hyprland.monitors.values.find(m => m.name === monitorName)
        if (!mon) return
        const monId = mon.id
        currentWs = currentOf(mon)
        const list = []
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject
            if (!o || !o.address || o.monitor !== monId || !o.mapped) continue
            const ws = o.workspace
            if (!ws || ws.id <= 0 || String(ws.name).startsWith("special:")) continue
            list.push({ address: o.address, ws: ws.id, title: o.title || "", cls: o.class || "",
                        floating: !!o.floating, fullscreen: !!o.fullscreen,
                        grouped: !!(o.grouped && o.grouped.length), fh: o.focusHistoryID !== undefined ? o.focusHistoryID : -1, x: o.at ? o.at[0] : 0, y: o.at ? o.at[1] : 0 })
        }
        list.sort((a, b) => a.ws - b.ws || a.x - b.x || a.y - b.y || (a.address < b.address ? -1 : 1))
        // optimistic moves stay applied until Hyprland confirms or they expire
        const now = Date.now(), ov = Object.assign({}, overrides)
        for (const w of list) {
            const o = ov[w.address]
            if (!o) continue
            if (w.ws === o.ws) delete ov[w.address]
            else if (now < o.until) w.ws = o.ws
            else { delete ov[w.address]; toast("Move didn't apply") }
        }
        overrides = ov
        const nm = {}, used = []
        for (const w of Hyprland.workspaces.values) {
            nm[String(w.id)] = (w.lastIpcObject && w.lastIpcObject.tiledLayout) || "dwindle"
            if (w.id > 0) used.push(w.id)
        }
        modes = nm; usedIds = used
        updateWsApp(list)
        const sig = list.map(w => w.address + ":" + w.ws + ":" + w.title + ":" + w.floating + w.fullscreen + w.grouped).join("|")
        if (sig !== windowSig) { windowSig = sig; windows = list }
        extendWorkspaces()
        if (!dragging && !flying) syncChips()
    }
    // main app of each workspace: the most recently focused window (lowest focusHistoryID), else the class with
    // the most windows, ties -> first seen. Only reassigned when something changed, so delegates don't rebind.
    function updateWsApp(list) {
        const by = {}
        for (const w of list) { if (!w.cls) continue; (by[w.ws] = by[w.ws] || []).push(w) }
        const out = {}
        for (const k of Object.keys(by)) {
            const ws = by[k]
            let best = null
            for (const w of ws) if (w.fh >= 0 && (best === null || w.fh < best.fh)) best = w
            if (best) { out[k] = best.cls; continue }
            const n = {}, order = []
            for (const w of ws) { if (!(w.cls in n)) { n[w.cls] = 0; order.push(w.cls) } n[w.cls]++ }
            let bc = order[0]
            for (const c of order) if (n[c] > n[bc]) bc = c
            out[k] = bc
        }
        const sig = JSON.stringify(out)
        if (sig !== wsAppSig) { wsAppSig = sig; wsApp = out }
    }
    function extendWorkspaces() {
        const ids = frozen.slice()
        let changed = false
        if (ids.length === 0) { for (let i = 1; i <= persistentWorkspaces; i++) ids.push(i); changed = true }
        for (const w of windows) if (w.ws > persistentWorkspaces && !ids.includes(w.ws)) { ids.push(w.ws); changed = true }
        if (currentWs > persistentWorkspaces && !ids.includes(currentWs)) { ids.push(currentWs); changed = true }
        if (changed) { ids.sort((a, b) => a - b); frozen = ids }
    }

    // Stable chip model: diff against the target instead of rebuilding delegates.
    ListModel { id: chipList }
    function syncChips() {
        const target = revealed >= 0 && revealed < frozen.length ? winsOf(wsAt(revealed)) : []
        for (let i = chipList.count - 1; i >= 0; i--)
            if (!target.some(w => w.address === chipList.get(i).address)) chipList.remove(i)
        for (let i = 0; i < target.length; i++) {
            const w = target[i]
            if (i < chipList.count && chipList.get(i).address === w.address) {
                const c = chipList.get(i)
                if (c.title !== w.title) chipList.setProperty(i, "title", w.title)
                if (c.ws !== w.ws) chipList.setProperty(i, "ws", w.ws)
                if (c.floating !== w.floating) chipList.setProperty(i, "floating", w.floating)
                if (c.fullscreen !== w.fullscreen) chipList.setProperty(i, "fullscreen", w.fullscreen)
                if (c.grouped !== w.grouped) chipList.setProperty(i, "grouped", w.grouped)
                continue
            }
            let j = -1
            for (let k = i + 1; k < chipList.count; k++) if (chipList.get(k).address === w.address) { j = k; break }
            if (j >= 0) chipList.move(j, i, 1)
            else chipList.insert(i, { address: w.address, title: w.title, cls: w.cls, ws: w.ws,
                                      floating: w.floating, fullscreen: w.fullscreen, grouped: w.grouped })
        }
    }
    property int pendingReveal: -1
    property int leaveSeq: 0
    // Keep-alive: chips of the petal being left retract on their own into it.
    ListModel { id: leaveList }
    function snapshotLeaving() {
        if (revealed < 0) return
        for (let i = 0; i < chipList.count; i++) {
            const it = chipRepeater.itemAt(i)
            if (!it || it.ghosted || it.rise < 0.02) continue
            const c = chipList.get(i)
            leaveList.append({ uid: ++leaveSeq, address: c.address, cls: c.cls, petal: revealed,
                               sa: it.sa, sr: it.sr, sx: it.sx, sy: it.sy, spx: it.spx, spy: it.spy, vert: vert, startP: Math.min(1, it.rise) })
        }
    }
    function dropLeaving(uid) {
        for (let k = 0; k < leaveList.count; k++) if (leaveList.get(k).uid === uid) { leaveList.remove(k); return }
    }
    // The rail (glass track behind the chips) belongs to its petal: it rides the same rise progress as the
    // chips (rail instance below) and, on a petal switch, a keep-alive copy retracts into the old petal.
    ListModel { id: railLeaveList }
    function dropRailLeaving(uid) {
        for (let k = 0; k < railLeaveList.count; k++) if (railLeaveList.get(k).uid === uid) { railLeaveList.remove(k); return }
    }
    ListModel { id: vRailLeaveList }
    function dropVRailLeaving(uid) {
        for (let k = 0; k < vRailLeaveList.count; k++) if (vRailLeaveList.get(k).uid === uid) { vRailLeaveList.remove(k); return }
    }
    function snapshotRail() {
        if (vert) {
            const vit = vRailOwner.itemAt(0)
            if (!vit || vit.p < 0.02 || vRows.length === 0 || !vSpawn) return
            vRailLeaveList.append({ uid: ++leaveSeq, rows_json: JSON.stringify(vRows), spx: vSpawn.x, spy: vSpawn.y, startP: Math.min(1, vit.p) })
            return
        }
        const it = railOwner.itemAt(0)
        if (!it || it.p < 0.02 || railRows.length === 0) return
        const rows = []
        for (const r of railRows) if (r) rows.push({ r: r.r, a0: r.a0, a1: r.a1 })
        railLeaveList.append({ uid: ++leaveSeq, petal: revealed, rows_json: JSON.stringify(rows), startP: Math.min(1, it.p) })
    }
    function setReveal(i) {
        if (i < 0 && (dragging || flying)) return      // a dragged chip's petal stays open
        if (i === revealed) { swapTimer.stop(); if (i >= 0 && !chipsOpen) chipsOpen = true; return }
        if (i < 0 && revealed >= 0 && chipList.count > 0) {
            chipsOpen = false                          // retract in place, then clear
            pendingReveal = -1
            swapTimer.restart()
        } else applyReveal(i)
    }
    function applyReveal(i) {
        swapTimer.stop()
        insIdx = -1; insSide = ""; hoverChip = -1
        if (i !== revealed) { snapshotLeaving(); snapshotRail() }
        // Destroy the old owner before changing petals: its cached row geometry
        // must never be retargeted to the next petal, even briefly.
        chipList.clear()
        revealed = i
        if (i >= 0) { syncChips(); chipsOpen = true } else chipsOpen = false
        if (dragging) updateInsertion()
    }

    // ------------------------------------------------------------ open / close
    function toggle() {
        if (pending) return
        if (shown && active) { closeBloom(); return }
        if (shown) { shown = false; clockAnim.stop() }
        beginOpen()
    }
    function beginOpen() {
        pending = true
        Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); Hyprland.refreshMonitors()
        cursorProc.running = true
    }
    function openAt(cx, cy) {
        const s = Quickshell.screens.find(x => cx >= x.x && cx < x.x + x.width && cy >= x.y && cy < x.y + x.height)
        if (!s) { console.warn("Bloom: cursor is not on a known screen"); pending = false; return }
        lm = layoutMode
        morphTimer.stop(); morphAnim.stop(); morphing = false; vK = vert ? 1 : 0
        targetScreen = s; monitorName = s.name; sw = s.width; sh = s.height
        curX = Math.max(th.hubR + 6, Math.min(sw - th.hubR - 6, cx - s.x))
        curY = Math.max(th.hubR + 6, Math.min(sh - th.hubR - 6, cy - s.y))
        px = curX; py = curY; driftX = 0; driftY = 0
        hovered = -1; pressedIdx = -1; pulse = -1; dragAddr = ""; dragging = false; flying = false; settingsOpen = false
        insIdx = -1; hoverChip = -1; toastShown = false; overrides = ({}); windowSig = ""
        frozen = []; windows = []
        aimRaw = -Math.PI / 2; aimAngle = aimRaw; aimHold = false
        revealed = -1; chipsOpen = false; chipList.clear(); leaveList.clear(); railLeaveList.clear(); vRailLeaveList.clear()
        rebuild(); reloadModes()
        // start the aim ring on the current workspace's petal
        const ci = frozen.indexOf(currentWs)
        if (ci >= 0) { aimRaw = baseMid(ci); aimAngle = aimRaw }
        anchorIdx = ci >= 0 ? ci : 0
        rimY = curY
        pending = false; active = true; shown = true; inputReady = true
        clockAnim.stop(); clockAnim.from = 0; clockAnim.to = clockTotal; clockAnim.duration = clockTotal; clockAnim.start()
        settleTimer.restart()
    }
    function closeBloom() {
        if (!shown || !active) return
        active = false; inputReady = false; settingsOpen = false
        if (morphing || morphTimer.running) { morphTimer.stop(); morphAnim.stop(); morphing = false; lm = layoutMode; clock = clockTotal; vK = vert ? 1 : 0 }
        dragging = false; dragAddr = ""; flying = false; pressedIdx = -1
        revealTimer.stop(); hideTimer.stop(); swapTimer.stop()
        chipsOpen = false
        clockAnim.stop(); clockAnim.from = clock; clockAnim.to = 0; clockAnim.duration = th.closeMs * Math.max(0.3, clock / clockTotal); clockAnim.start()
    }
    NumberAnimation { id: clockAnim; target: root; property: "clock"; easing.type: Easing.Linear
        onFinished: { if (!root.active) { root.shown = false; chipList.clear(); leaveList.clear(); railLeaveList.clear(); vRailLeaveList.clear(); root.revealed = -1; root.applyLayout() } } }

    // ---------------------------------------------------------------- actions
    function hypr(code) { Hyprland.dispatch(code) }
    function toast(msg) { toastText = msg; toastShown = shown; toastTimer.restart(); if (!shown) Quickshell.execDetached(["notify-send", "-a", "Bloom", msg]) }
    property int verifyWs: -1
    function doSwitch(ws) {
        currentWs = ws
        hypr('hl.dsp.focus({ workspace = "' + ws + '" })')
        verifyWs = ws; verifyTimer.restart()
    }
    function applyMove(addr, ws, beforeAddr, side) {
        const ov = Object.assign({}, overrides); ov[addr] = { ws: ws, until: Date.now() + th.reconcileMs }; overrides = ov
        const list = windows.slice()
        const at = list.findIndex(w => w.address === addr)
        if (at < 0) return
        const moving = Object.assign({}, list[at], { ws: ws })
        list.splice(at, 1)
        if (beforeAddr) { const t = list.findIndex(w => w.address === beforeAddr); list.splice(t + (side === "r" ? 1 : 0), 0, moving) }
        else list.push(moving)
        windows = list
    }
    function doMove(addr, ws, follow) {
        hypr('hl.dsp.window.move({ workspace = "' + ws + '", window = "address:' + addr + '", follow = ' + (follow ? "true" : "false") + ' })')
        if (follow) currentWs = ws
        refreshTimer.restart()
    }
    function doPlace(a, b, side) {
        if (placeProc.running) { placeQueue.push([a, b, side]); return }   // one placement at a time; run the next on exit
        runPlace(a, b, side)
    }
    property var placeQueue: []
    function runPlace(a, b, side) {
        placeProc.command = ["python3", "-B", backend, "place", a, b, side]
        placeProc.running = true
    }
    function nextPlace() {
        const n = placeQueue.shift()
        if (n) runPlace(n[0], n[1], n[2])
    }

    // ---------------------------------------------------------------- pointer
    // ---- settings card
    property bool settingsOpen: false
    property real settingsK: settingsOpen ? 1 : 0
    Behavior on settingsK { NumberAnimation { duration: root.fdur(root.settingsOpen ? root.th.cardInMs : root.th.cardOutMs); easing.type: root.settingsOpen ? Easing.OutCubic : Easing.InCubic } }
    function openSettings() {
        if (!shown || !active || settingsOpen) return
        hovered = -1; pressedIdx = -1; dragAddr = ""; dragWin = null
        revealTimer.stop(); hideTimer.stop()
        if (revealed >= 0) setReveal(-1)
        settingsOpen = true
    }
    function closeSettings() { settingsOpen = false }
    function aimTo(angle) { if (!aimHold) aimRaw += G.wrap(angle - aimRaw) }
    function pointerMoved(x, y, pressed) {
        if (!inputReady || settingsOpen || morphing) return
        px = x; py = y
        const cx = hx + driftX, cy = hy + driftY
        const dx = x - cx, dy = y - cy, r = Math.hypot(dx, dy), ang = Math.atan2(dy, dx)
        let ox = (x - hx) * th.driftGain, oy = (y - hy) * th.driftGain
        const m = Math.hypot(ox, oy)
        if (m > th.driftMax) { ox *= th.driftMax / m; oy *= th.driftMax / m }
        driftX = ox; driftY = oy
        if (pressed && dragAddr !== "" && !dragging && Math.hypot(x - downX, y - downY) > th.dragThreshold) beginDrag()
        if (dragging) { gx = x; gy = y - th.ghostLift }
        if (pressed && !dragging) return
        const idx = itemHit(x, y)
        const region = idx < 0 && inRevealRegion(x, y)
        if (vert) rimY = y
        else {
            aimHold = aimHold ? r < th.aimDeadZone + th.aimDeadHyst : r < th.aimDeadZone
            if (idx >= 0) aimTo(ang)
            else if (region) { aimTo(baseMid(revealed)) }
            else aimTo(ang)
        }
        if (idx >= 0) {
            hideTimer.stop()
            if (idx !== hovered) { hovered = idx; revealTimer.stop(); if (idx !== revealed) revealTimer.restart() }
            // leaving the revealed petal for another one: its chips start retracting at once;
            // coming back reverses them from wherever they are
            if (!dragging && revealed >= 0) {
                if (idx !== revealed && chipsOpen) chipsOpen = false
                else if (idx === revealed && !chipsOpen) setReveal(idx)
            }
        } else {
            hovered = -1; revealTimer.stop()
            if (region) hideTimer.stop()
            else if (revealed >= 0 && !hideTimer.running) hideTimer.start()
        }
        hoverChip = dragging ? -1 : chipAt(x, y)
        if (dragging) updateInsertion()
    }
    function updateInsertion() {
        const j = chipAt(px, py)
        if (j >= 0) {
            const w = chipList.get(j)
            if (w.address !== dragAddr && !w.floating && !w.fullscreen && !w.grouped && modes[String(w.ws)] === "dwindle") {
                insIdx = j; insSide = px < chipPanel(j).x ? "l" : "r"; return
            }
        }
        insIdx = -1; insSide = ""
    }
    function pointerPressed(x, y) {
        if (settingsOpen || morphing) return
        downX = x; downY = y; px = x; py = y
        const j = chipAt(x, y)
        if (j >= 0) {
            const w = chipList.get(j)
            dragWin = { address: w.address, cls: w.cls, title: w.title, ws: w.ws }
            dragAddr = w.address; dragSrcWs = w.ws; dragSrcSlot = j
            dragSrcPetal = revealed
        } else { dragWin = null; dragAddr = ""; dragSrcSlot = -1; dragSrcWs = -1 }
        dragging = false
        pressedIdx = dragAddr === "" ? itemHit(x, y) : -1
    }
    function beginDrag() {
        dragging = true; hoverChip = -1
        gx = px; gy = py - th.ghostLift
        fadeGhost = 1
    }
    function chipIndexOf(addr) {
        for (let k = 0; k < chipList.count; k++) if (chipList.get(k).address === addr) return k
        return -1
    }
    function pointerReleased(x, y, shift) {
        if (settingsOpen || morphing) return
        let t = itemHit(x, y)
        const onSettings = t === settingsIndex     // Settings is not a drop target: a drop there cancels
        if (onSettings) t = -1
        pressedIdx = -1
        if (dragging && dragWin) {
            px = x; py = y; updateInsertion()
            const placing = insIdx >= 0, side = insSide
            const targetAddr = placing ? chipList.get(insIdx).address : ""
            if (placing) t = revealed
            else if (t < 0 && chipAt(x, y) >= 0) t = revealed
            const dest = t >= 0 ? wsAt(t) : dragSrcWs
            const success = placing || (t >= 0 && dest !== dragSrcWs)
            const addr = dragAddr
            let landX = x, landY = y, vanish = false
            if (success) {
                applyMove(addr, dest, placing ? targetAddr : "", side)
                if (t !== revealed) { hovered = t; snapshotLeaving(); snapshotRail(); chipList.clear(); revealed = t; chipsOpen = true }
                syncChips()
                if (placing) doPlace(addr, targetAddr, side); else doMove(addr, dest, shift)
                pulse = t; pulseTimer.restart()
                const j = chipIndexOf(addr)
                if (j >= 0) { const c = chipPanel(j); landX = c.x; landY = c.y }
                else if (t >= 0) { const p = landingPoint(t); landX = p.x; landY = p.y; vanish = true }
                if (placing || shift) closeTimer.restart()
            } else {
                // cancel: fly straight back into the source slot
                if (revealed !== dragSrcPetal) { swapTimer.stop(); applyReveal(dragSrcPetal) }
                const j = chipIndexOf(addr)
                const c = chipPanel(j >= 0 ? j : dragSrcSlot)
                landX = c.x; landY = c.y
            }
            insIdx = -1; insSide = ""
            flying = true; dragging = false
            flyX.to = landX; flyY.to = landY; flyFade.to = vanish ? 0 : 1
            flyAnim.stop(); flyAnim.start()
        } else if (dragAddr === "") {
            if (onSettings) openSettings()
            else if (t >= 0) { doSwitch(wsAt(t)); closeBloom() }
            else closeBloom()
        } else { dragAddr = ""; dragWin = null }
    }

    // ---------------------------------------------------------------- plumbing
    IpcHandler {
        target: "io.github.chrisdavila7.bloom"
        function toggle(): void { root.toggle() }
        function layout(name: string): string { return root.setLayout(name) ? root.layoutMode : "error: layout must be bloom or vertical" }
        function theme(name: string): string { return root.setTheme(name) ? root.themeMode : "error: theme must be neutral or omarchy" }
        function status(): string { return JSON.stringify({open: root.shown && root.active, shown: root.shown, pending: root.pending, layout: root.layoutMode, theme: root.themeMode, reducedMotion: root.th.reduced}) }
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector { id: cursorOut }
        onExited: function (code) {
            if (code !== 0) { console.warn("Bloom: cursorpos failed"); root.pending = false; return }
            try { const c = JSON.parse(cursorOut.text); root.openAt(c.x, c.y) } catch (e) { console.warn("Bloom: " + e); root.pending = false }
        }
    }
    Process {
        id: placeProc
        stdout: StdioCollector { id: placeOut }
        stderr: StdioCollector { id: placeErr }
        onExited: function (code) {
            if (code !== 0) { root.toast("Couldn't place window"); console.warn("Bloom place: " + placeErr.text) }
            else try { const r = JSON.parse(placeOut.text); if (r.result === "fallback") root.toast("Moved here (" + r.reason + ")") } catch (e) {}
            Qt.callLater(root.nextPlace)
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (root.shown) eventTimer.restart() }
    }
    Timer { id: eventTimer; interval: th.eventDebounceMs; onTriggered: { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); Hyprland.refreshMonitors(); settleTimer.restart() } }
    Timer { id: settleTimer; interval: th.settleMs; onTriggered: if (root.shown) root.rebuild() }
    Timer { id: refreshTimer; interval: th.refreshMs; onTriggered: { Hyprland.refreshToplevels(); settleTimer.restart() } }
    Timer { id: revealTimer; interval: th.revealMs; onTriggered: if (root.hovered >= 0) root.setReveal(root.hovered === root.settingsIndex ? -1 : root.hovered) }
    Timer { id: hideTimer; interval: th.hideMs; onTriggered: root.setReveal(-1) }
    Timer { id: swapTimer; interval: th.chipFallMs + 15; onTriggered: root.applyReveal(root.pendingReveal) }
    Timer { id: pulseTimer; interval: th.pulseHoldMs; onTriggered: root.pulse = -1 }
    Timer { id: closeTimer; interval: th.doneCloseMs; onTriggered: root.closeBloom() }
    Timer { id: toastTimer; interval: th.toastMs; onTriggered: root.toastShown = false }
    Timer { id: verifyTimer; interval: th.reconcileMs
        onTriggered: { const m = Hyprland.monitors.values.find(x => x.name === root.monitorName); if (m && root.currentOf(m) !== root.verifyWs) root.toast("Couldn't switch to workspace " + root.verifyWs) } }
    ParallelAnimation {
        id: flyAnim
        NumberAnimation { id: flyX; target: root; property: "gx"; duration: root.dur(th.flyMs); easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { id: flyY; target: root; property: "gy"; duration: root.dur(th.flyMs); easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { id: flyFade; target: root; property: "fadeGhost"; duration: root.dur(th.flyMs); easing.type: Easing.InQuad }
        onFinished: { root.flying = false; root.dragAddr = ""; root.dragWin = null; root.fadeGhost = 1; root.syncChips() }
    }

    // ------------------------------------------------------------------ veil
    // Input-transparent vignette on the Top layer; not blurred.
    PanelWindow {
        id: veil
        visible: root.shown
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "bloom-veil"
        Shape {
            anchors.fill: parent
            opacity: Math.max(0, Math.min(1, root.clock / (root.clockTotal * 0.85)))
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.vigX; centerY: root.vigY; focalX: root.vigX; focalY: root.vigY
                    centerRadius: Math.hypot(root.sw, root.sh) * 0.82
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: root.th.vignetteClear; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.th.vignetteMax) }
                }
                PathSvg { path: "M0 0 H" + root.sw + " V" + root.sh + " H0 Z" }
            }
        }
    }

    // ----------------------------------------------------------------- bloom
    PanelWindow {
        id: panel
        visible: root.shown
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "bloom"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onPositionChanged: function (m) { root.pointerMoved(m.x, m.y, pressed) }
            onPressed: function (m) { root.pointerPressed(m.x, m.y) }
            onReleased: function (m) { root.pointerReleased(m.x, m.y, (m.modifiers & Qt.ShiftModifier) !== 0) }
        }

        // bloom layout: petals + recessed well
        Item {
            id: bloom
            x: root.hx + root.driftX
            y: root.hy + root.driftY
            visible: root.vK < 0.999
            readonly property real hubProg: root.th.reduced ? 1 : root.active ? root.easeOutBack(Math.min(1, root.clock / root.th.petalMs)) : Math.min(1, root.clock / root.th.petalMs)

            // petals
            Repeater {
                model: root.count
                delegate: Item {
                    id: pet
                    required property int index
                    readonly property var g: root.lay[index] || ({ a0: 0, a1: 0.1, mid: 0, ri: 40, ro: 92, roH: 98 })
                    readonly property bool settings: index === root.frozen.length   // the last petal opens the settings card
                    readonly property int wid: settings ? -1 : root.frozen[index]
                    readonly property int nwin: settings ? 0 : root.winCount(wid)
                    readonly property string wcls: settings || nwin === 0 ? "" : (root.wsApp[String(wid)] || "")
                    readonly property bool isCurrent: !settings && wid === root.currentWs
                    readonly property real prog: root.petalProg(index, root.clock)
                    // the Settings petal stays in its hovered state (grown, rim catch) while its card is open
                    readonly property bool isHover: root.hovered === index || (settings && root.settingsOpen)
                    property real hov: isHover ? 1 : 0
                    property real cur: isCurrent ? 1 : 0
                    property real occ: (settings || nwin > 0) ? 1 : 0
                    property real press: root.pressedIdx === index ? 1 : 0
                    property real drop: (!settings && root.dragging && isHover && wid !== root.dragSrcWs) ? 1 : 0
                    property real pul: root.pulse === index ? 1 : 0
                    property real rim: isHover ? 1 : 0
                    Behavior on hov { NumberAnimation { duration: root.dur(root.th.hoverMs); easing.type: Easing.OutCubic } }
                    Behavior on rim { NumberAnimation { duration: root.dur(pet.isHover ? root.th.rimCatchInMs : root.th.rimCatchOutMs); easing.type: pet.isHover ? Easing.OutCubic : Easing.InCubic } }
                    Behavior on cur { NumberAnimation { duration: root.dur(root.th.hoverMs * 2); easing.type: Easing.OutCubic } }
                    Behavior on occ { NumberAnimation { duration: root.dur(root.th.hoverMs * 2) } }
                    Behavior on press { NumberAnimation { duration: root.dur(root.th.pressMs); easing.type: Easing.OutCubic } }
                    Behavior on drop { NumberAnimation { duration: root.dur(root.th.hoverMs); easing.type: Easing.OutCubic } }
                    Behavior on pul { NumberAnimation { duration: root.dur(root.th.pulseMs); easing.type: Easing.OutCubic } }
                    readonly property real p: Math.min(prog, 1.1)
                    readonly property real rIn: root.th.hubR * 0.9 + (g.ri + press * 1.5 - root.th.hubR * 0.9) * p
                    readonly property real rOut: root.th.hubR + (g.ro + root.th.hoverGrow * hov + pul * 4 - press * 3 - root.th.hubR) * p
                    readonly property real half: root.th.gap / 2
                    readonly property real s0: rIn / Math.max(rOut, 1)   // inner radius as a fraction of the outer (depth-light gradient)
                    readonly property string d: G.petalPath(root.th.boundary, root.th.boundary, rIn, rOut, g.a0, g.a1, root.th.gap, root.th.corner)
                    // the full wedge (no gap) minus the petal = the petal's half of the seam on each side
                    // the seam stops at the neighbours' resting outer edge (rSeam), so a hovered / pulsing petal grows past it without a dark stub
                    readonly property real rSeam: Math.min(rOut, root.th.hubR + (g.ro - root.th.hubR) * p)
                    readonly property string dSeam: G.petalPath(root.th.boundary, root.th.boundary, rIn, rSeam, g.a0, g.a1, root.th.gap, root.th.corner)
                    readonly property string seam: dSeam === "" ? "" : G.seamPath(root.th.boundary, root.th.boundary, rIn - root.th.seamBleed, rSeam + root.th.seamBleed, g.a0, g.a1, root.th.corner + half) + " " + dSeam
                    readonly property string edge: G.arcPath(root.th.boundary, root.th.boundary, rOut - 0.6, g.a0 + (half + root.th.corner + 1) / rOut, g.a1 - (half + root.th.corner + 1) / rOut)
                    // rim catch: lit band just inside the outer edge, clamped to the petal's straight span
                    readonly property real rimMargin: (half + root.th.corner + 1) / Math.max(rOut, 1)
                    readonly property real rimLo: g.a0 + rimMargin
                    readonly property real rimHi: Math.max(rimLo + 0.002, g.a1 - rimMargin)
                    readonly property real rimC: G.clamp(root.aimAngle, rimLo, rimHi)
                    readonly property real rimSpan: Math.max(0.002, rimHi - rimLo)
                    readonly property real rimS: Math.max(0.002, root.th.rimCatchSpread * (g.a1 - g.a0))
                    readonly property real rimStart: -rimHi * 180 / Math.PI   // Qt conical angle runs counter-clockwise on screen; position 0 sits at the petal's end angle and grows as the angle decreases
                    readonly property real rimP: (rimHi - rimC) / (2 * Math.PI)
                    readonly property real rimR: rimS / (2 * Math.PI)
                    readonly property string rimBand: G.bandPath(root.th.boundary, root.th.boundary, rOut - root.th.rimCatchInset - root.th.rimCatchWidth, rOut - root.th.rimCatchInset, rimLo, rimHi)
                    readonly property string tickPath: G.arcPath(root.th.boundary, root.th.boundary, rOut - root.th.tickInset, g.mid - root.th.tickLen / 2 / Math.max(rOut - root.th.tickInset, 1), g.mid + root.th.tickLen / 2 / Math.max(rOut - root.th.tickInset, 1))
                    readonly property real fillA: root.th.glassEmpty + (root.th.glassOccupied - root.th.glassEmpty) * occ + (root.th.glassHover - root.th.glassOccupied) * hov
                    // morph: the petal travels to / from its column slot while shrinking / growing and fading
                    readonly property real rmid: (rIn + rOut) / 2
                    readonly property real cpx: rmid * Math.cos(g.mid)
                    readonly property real cpy: rmid * Math.sin(g.mid)
                    readonly property var csl: CG.itemCenter(root.colLay, index) || ({ x: root.hx, y: root.hy })
                    x: (csl.x - root.hx - cpx) * root.vK
                    y: (csl.y - root.hy - cpy) * root.vK
                    transform: Scale { origin.x: pet.cpx; origin.y: pet.cpy; xScale: root.th.morphScale + (1 - root.th.morphScale) * (1 - root.vK); yScale: xScale }
                    opacity: root.openFade(prog, 1.5) * (1 - root.vK)

                    Shape {
                        x: -root.th.boundary; y: -root.th.boundary
                        width: root.th.boundary * 2; height: root.th.boundary * 2
                        preferredRendererType: Shape.CurveRenderer
                        // glass seam (the hairline gaps between petals), blurred like the glass
                        ShapePath {
                            strokeWidth: -1; fillRule: ShapePath.OddEvenFill
                            fillColor: Qt.rgba(0, 0, 0, root.th.seamAlpha)
                            PathSvg { path: pet.seam }
                        }
                        // smoked glass body
                        ShapePath {
                            strokeWidth: -1
                            fillColor: Qt.rgba(root.th.glass.r + root.th.hoverLift * pet.hov, root.th.glass.g + root.th.hoverLift * 1.1 * pet.hov, root.th.glass.b + root.th.hoverLift * 1.3 * pet.hov, pet.fillA)
                            PathSvg { path: pet.d }
                        }
                        // accent wash while a window is dragged over this petal
                        ShapePath {
                            strokeWidth: -1
                            fillColor: Qt.rgba(root.th.accent.r, root.th.accent.g, root.th.accent.b, 0.34 * pet.drop + 0.20 * pet.pul)
                            PathSvg { path: pet.d }
                        }
                        // depth light: shade toward the well (inner edge), light toward the outer edge; smooth quadratic ramps
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: RadialGradient {
                                centerX: root.th.boundary; centerY: root.th.boundary; focalX: centerX; focalY: centerY
                                centerRadius: Math.max(1, pet.rOut)
                                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner) }
                                GradientStop { position: pet.s0; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner) }
                                GradientStop { position: pet.s0 + (1 - pet.s0) * 0.125; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * 0.5625) }
                                GradientStop { position: pet.s0 + (1 - pet.s0) * 0.25; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * 0.25) }
                                GradientStop { position: pet.s0 + (1 - pet.s0) * 0.375; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * 0.0625) }
                                GradientStop { position: pet.s0 + (1 - pet.s0) * 0.5; color: Qt.rgba(0, 0, 0, 0) }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
                            }
                            PathSvg { path: pet.d }
                        }
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: RadialGradient {
                                centerX: root.th.boundary; centerY: root.th.boundary; focalX: centerX; focalY: centerY
                                centerRadius: Math.max(1, pet.rOut)
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                                GradientStop { position: pet.s0 + (1 - pet.s0) * 0.5; color: Qt.rgba(1, 1, 1, 0) }
                                GradientStop { position: pet.s0 + (1 - pet.s0) * 0.625; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * 0.0625) }
                                GradientStop { position: pet.s0 + (1 - pet.s0) * 0.75; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * 0.25) }
                                GradientStop { position: pet.s0 + (1 - pet.s0) * 0.875; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * 0.5625) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, root.th.depthLightTop) }
                            }
                            PathSvg { path: pet.d }
                        }
                        // top light
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: LinearGradient {
                                x1: 0; y1: root.th.boundary - 130; x2: 0; y2: root.th.boundary + 130
                                GradientStop { position: 0.0; color: root.th.topLight }
                                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
                            }
                            PathSvg { path: pet.d }
                        }
                        // light inner highlight on the outer edge
                        ShapePath {
                            strokeWidth: 1; strokeColor: root.th.edgeLight; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathSvg { path: pet.edge }
                        }
                        // drag target: accent outline
                        ShapePath {
                            strokeWidth: 1.6; strokeColor: Qt.rgba(root.th.accent.r, root.th.accent.g, root.th.accent.b, 0.95 * pet.drop); fillColor: "transparent"
                            PathSvg { path: pet.d }
                        }
                    }

                    // hover rim catch (own Shape: conical gradients need the generic renderer)
                    Shape {
                        x: -root.th.boundary; y: -root.th.boundary
                        width: root.th.boundary * 2; height: root.th.boundary * 2
                        preferredRendererType: Shape.GeometryRenderer
                        antialiasing: true
                        layer.enabled: true; layer.samples: 4; layer.smooth: true
                        // hover rim catch: white light on the outer edge, brightest at the pointer angle
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: ConicalGradient {
                                centerX: root.th.boundary; centerY: root.th.boundary
                                angle: pet.rimStart
                                GradientStop { position: Math.max(0, pet.rimP - pet.rimR);        color: Qt.rgba(1, 1, 1, 0) }
                                GradientStop { position: Math.max(0, pet.rimP - pet.rimR * 0.75); color: Qt.rgba(1, 1, 1, root.th.rimCatchAlpha * pet.rim * 0.04) }
                                GradientStop { position: Math.max(0, pet.rimP - pet.rimR * 0.5);  color: Qt.rgba(1, 1, 1, root.th.rimCatchAlpha * pet.rim * 0.25) }
                                GradientStop { position: Math.max(0, pet.rimP - pet.rimR * 0.25); color: Qt.rgba(1, 1, 1, root.th.rimCatchAlpha * pet.rim * 0.65) }
                                GradientStop { position: pet.rimP;                                color: Qt.rgba(1, 1, 1, root.th.rimCatchAlpha * pet.rim) }
                                GradientStop { position: Math.min(1, pet.rimP + pet.rimR * 0.25); color: Qt.rgba(1, 1, 1, root.th.rimCatchAlpha * pet.rim * 0.65) }
                                GradientStop { position: Math.min(1, pet.rimP + pet.rimR * 0.5);  color: Qt.rgba(1, 1, 1, root.th.rimCatchAlpha * pet.rim * 0.25) }
                                GradientStop { position: Math.min(1, pet.rimP + pet.rimR * 0.75); color: Qt.rgba(1, 1, 1, root.th.rimCatchAlpha * pet.rim * 0.04) }
                                GradientStop { position: Math.min(1, pet.rimP + pet.rimR);        color: Qt.rgba(1, 1, 1, 0) }
                            }
                            PathSvg { path: pet.rimBand }
                        }
                    }

                    // current workspace tick, above the rim catch
                    Shape {
                        x: -root.th.boundary; y: -root.th.boundary
                        width: root.th.boundary * 2; height: root.th.boundary * 2
                        preferredRendererType: Shape.CurveRenderer
                        // current workspace: accent tick, drawn above the rim catch
                        ShapePath {
                            strokeWidth: root.th.tickWidth; strokeColor: Qt.rgba(root.th.accent.r, root.th.accent.g, root.th.accent.b, root.th.tickAlpha * pet.cur)
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathSvg { path: pet.tickPath }
                        }
                    }

                    // app watermark: main app of the workspace, grayscale, behind the number (upright, unscaled)
                    AppMark {
                        readonly property real rm: (pet.rIn + pet.rOut) / 2
                        x: rm * Math.cos(pet.g.mid) - width / 2; y: rm * Math.sin(pet.g.mid) - height / 2
                        size: Math.round(Math.max(0.01, pet.g.ro - pet.g.ri) * root.th.watermarkScale)
                        fadeMs: root.th.watermarkFadeMs
                        cls: pet.wcls
                        opacity: root.th.watermarkAlpha + root.th.watermarkHoverAdd * pet.hov
                    }

                    // engraved number
                    Item {
                        readonly property real rm: (pet.rIn + pet.rOut) / 2
                        x: rm * Math.cos(pet.g.mid); y: rm * Math.sin(pet.g.mid)
                        scale: (1 + 0.28 * pet.hov) * (1 - 0.06 * pet.press)
                        Text {
                            anchors.centerIn: parent; anchors.verticalCenterOffset: 1
                            text: pet.settings ? (root.glyphOk ? root.th.glyphGear : "\u2699\ufe0e") : String(pet.wid)
                            color: Qt.rgba(0, 0, 0, 0.5); font.family: pet.settings ? root.th.iconFont : root.th.font; font.pixelSize: pet.settings ? root.gearPx(root.th.settingsGlyphPx) : root.th.numberPx; font.weight: Font.Medium
                            font.features: ({ "tnum": 1 }); textFormat: Text.PlainText
                        }
                        Text {
                            anchors.centerIn: parent
                            text: pet.settings ? (root.glyphOk ? root.th.glyphGear : "\u2699\ufe0e") : String(pet.wid)
                            color: root.th.text; opacity: pet.settings ? 0.85 + 0.15 * pet.hov : 0.55 + 0.45 * pet.occ + 0.2 * pet.hov
                            font.family: pet.settings ? root.th.iconFont : root.th.font; font.pixelSize: pet.settings ? root.gearPx(root.th.settingsGlyphPx) : root.th.numberPx; font.weight: Font.Medium
                            font.features: ({ "tnum": 1 }); textFormat: Text.PlainText
                        }
                        // occupancy pips
                        Row {
                            visible: !pet.settings && pet.nwin > 0
                            x: -width / 2
                            y: root.th.numberPx / 2 + 3
                            spacing: 3
                            Repeater {
                                model: Math.min(pet.nwin, 4)
                                delegate: Rectangle { width: 3; height: 3; radius: 1.5; color: root.th.text; opacity: 0.55 }
                            }
                        }
                    }
                }
            }

            // recessed well: near-transparent, defined by an inner shadow (light from above).
            // Radius = petals' inner radius (scaled with the ring) - wellGap, so well + petals read as one piece.
            Item {
                id: well
                readonly property real r: Math.max(0.01, (root.th.innerR * root.ringK - root.th.wellGap) * bloom.hubProg)
                readonly property real d: r * 2
                readonly property real off: r * root.th.wellShadowOffsetK
                readonly property real s0: root.th.wellShadowStart
                readonly property real lipA: root.th.wellLipAlpha
                readonly property real sa: root.th.wellShadowAlpha
                readonly property string circ: "M0 " + r + " A" + r + " " + r + " 0 1 1 " + d + " " + r + " A" + r + " " + r + " 0 1 1 0 " + r
                // the fill runs out to the petals' inner edge (r + wellGap): no dark ring, no unblurred crack between well and petals
                readonly property real rf: r + root.th.wellGap + 0.5   // 0.5 px under the petals' inner edge: no antialias crack
                readonly property string circFill: "M" + (-root.th.wellGap) + " " + r + " A" + rf + " " + rf + " 0 1 1 " + (d + root.th.wellGap) + " " + r + " A" + rf + " " + rf + " 0 1 1 " + (-root.th.wellGap) + " " + r
                x: -r; y: -r; width: d; height: d
                opacity: root.openFade(bloom.hubProg, 1) * (1 - root.vK)
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: -1; fillColor: Qt.rgba(root.th.wellFillColor.r, root.th.wellFillColor.g, root.th.wellFillColor.b, root.th.wellFillAlpha)
                        PathSvg { path: well.circFill }
                    }
                    // inner shadow: gradient centre pushed down, so the upper rim is darkest; quadratic
                    // ramp (several stops) so there is no visible band where it starts
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            centerX: well.r; centerY: well.r + well.off
                            focalX: centerX; focalY: centerY
                            centerRadius: well.r
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: well.s0; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: well.s0 + (1 - well.s0) * 0.25; color: Qt.rgba(0, 0, 0, well.sa * 0.0625) }
                            GradientStop { position: well.s0 + (1 - well.s0) * 0.5; color: Qt.rgba(0, 0, 0, well.sa * 0.25) }
                            GradientStop { position: well.s0 + (1 - well.s0) * 0.75; color: Qt.rgba(0, 0, 0, well.sa * 0.5625) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, well.sa) }
                        }
                        PathSvg { path: well.circ }
                    }
                    // faint lip on the lower inner rim
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            centerX: well.r; centerY: well.r - well.off
                            focalX: centerX; focalY: centerY
                            centerRadius: well.r
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: 0.84; color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: 0.92; color: Qt.rgba(1, 1, 1, well.lipA * 0.3) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, well.lipA) }
                        }
                        PathSvg { path: well.circ }
                    }
                }
            }

        }

        // vertical layout: the workspace column (slot cells with hairline gaps; slots unfold from the current one)
        Item {
            id: column
            visible: root.vK > 0.001
            x: root.driftX; y: root.driftY
            Repeater {
                model: root.vK > 0.001 || root.vert ? root.itemCount : 0
                delegate: Item {
                    id: sl
                    required property int index
                    readonly property bool special: index === root.frozen.length   // the last slot opens the settings card
                    readonly property int wid: special ? -1 : root.frozen[index]
                    readonly property int nwin: special ? 0 : root.winCount(wid)
                    readonly property string wcls: special || nwin === 0 ? "" : (root.wsApp[String(wid)] || "")
                    readonly property bool isCurrent: !special && wid === root.currentWs
                    readonly property real prog: root.petalProg(index, root.clock)
                    readonly property bool isHover: root.hovered === index || (special && root.settingsOpen)
                    property real hov: isHover ? 1 : 0
                    property real cur: isCurrent ? 1 : 0
                    property real occ: (special || nwin > 0) ? 1 : 0
                    property real emp: (!special && !isCurrent && nwin === 0) ? 1 : 0
                    property real press: root.pressedIdx === index ? 1 : 0
                    property real drop: (!special && root.dragging && isHover && wid !== root.dragSrcWs) ? 1 : 0
                    property real pul: root.pulse === index ? 1 : 0
                    property real rim: isHover ? 1 : 0
                    Behavior on hov { NumberAnimation { duration: root.dur(root.th.hoverMs); easing.type: Easing.OutCubic } }
                    Behavior on rim { NumberAnimation { duration: root.dur(sl.isHover ? root.th.rimCatchInMs : root.th.rimCatchOutMs); easing.type: sl.isHover ? Easing.OutCubic : Easing.InCubic } }
                    Behavior on cur { NumberAnimation { duration: root.dur(root.th.hoverMs * 2); easing.type: Easing.OutCubic } }
                    Behavior on occ { NumberAnimation { duration: root.dur(root.th.hoverMs * 2) } }
                    Behavior on emp { NumberAnimation { duration: root.dur(root.th.colEmptyMs); easing.type: Easing.OutCubic } }
                    Behavior on press { NumberAnimation { duration: root.dur(root.th.colPressMs); easing.type: Easing.OutCubic } }
                    Behavior on drop { NumberAnimation { duration: root.dur(root.th.hoverMs); easing.type: Easing.OutCubic } }
                    Behavior on pul { NumberAnimation { duration: root.dur(root.th.pulseMs); easing.type: Easing.OutCubic } }
                    readonly property var rc: CG.slotRect(root.colLay, index, root.th)
                    readonly property real centerY: root.colLay.y + root.colLay.height / 2
                    readonly property real p: Math.min(prog, 1.1)
                    readonly property bool lw: root.colLay.direction < 0
                    readonly property real widen: root.th.hoverGrow * hov
                    readonly property real rTop: rc.topInner ? root.th.colInnerRadius : root.th.colRadius
                    readonly property real rBot: rc.botInner ? root.th.colInnerRadius : root.th.colRadius
                    readonly property real fillA: root.th.glassEmpty + (root.th.glassOccupied - root.th.glassEmpty) * occ + (root.th.glassHover - root.th.glassOccupied) * hov
                    // morph: the slot travels to / from the bloom petal that holds the same workspace (Settings: the Settings petal)
                    readonly property var pl: root.lay[index]
                    readonly property real pmid: pl ? (pl.ri + pl.ro) / 2 : 0
                    readonly property real mpx: pl ? root.hx + pmid * Math.cos(pl.mid) : root.hx
                    readonly property real mpy: pl ? root.hy + pmid * Math.sin(pl.mid) : root.hy
                    readonly property real mdx: (mpx - (rc.x + rc.w / 2)) * (1 - root.vK)
                    readonly property real mdy: (mpy - (rc.y + rc.h / 2)) * (1 - root.vK)
                    x: rc.x - (lw ? widen : 0) + mdx; width: rc.w + widen
                    y: centerY - rc.h / 2 + (rc.y + rc.h / 2 - centerY) * p + mdy; height: rc.h
                    transform: Scale { origin.x: sl.width / 2; origin.y: sl.height / 2; xScale: root.th.morphScale + (1 - root.th.morphScale) * root.vK; yScale: xScale }
                    opacity: root.openFade(prog, 1.5) * root.vK
                    z: hov > 0.01 ? 2 : 0

                    // glass seam in the hairline gap above this slot (same near-black as the bloom's seams)
                    Rectangle {
                        visible: sl.rc.topInner
                        x: 0; width: sl.width; y: -root.th.slotHair; height: root.th.slotHair
                        color: Qt.rgba(0, 0, 0, root.th.seamAlpha)
                    }
                    // a hovered slot is wider than its lower neighbour: seam under its widened strip as well
                    Rectangle {
                        visible: sl.rc.botInner && sl.hov > 0.01
                        x: sl.lw ? 0 : sl.rc.w; width: sl.widen; y: sl.height; height: root.th.slotHair
                        color: Qt.rgba(0, 0, 0, root.th.seamAlpha)
                    }
                    // smoked glass body
                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: sl.rTop; topRightRadius: sl.rTop; bottomLeftRadius: sl.rBot; bottomRightRadius: sl.rBot
                        color: Qt.rgba(root.th.glass.r + root.th.hoverLift * sl.hov, root.th.glass.g + root.th.hoverLift * 1.1 * sl.hov, root.th.glass.b + root.th.hoverLift * 1.3 * sl.hov, sl.fillA)
                    }
                    // accent wash while a window is dragged over this slot
                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: sl.rTop; topRightRadius: sl.rTop; bottomLeftRadius: sl.rBot; bottomRightRadius: sl.rBot
                        color: Qt.rgba(root.th.accent.r, root.th.accent.g, root.th.accent.b, 0.34 * sl.drop + 0.20 * sl.pul)
                    }
                    // depth light: horizontal ramps across the slot; dark on the screen side, light on the centre-facing side
                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: sl.rTop; topRightRadius: sl.rTop; bottomLeftRadius: sl.rBot; bottomRightRadius: sl.rBot
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * (sl.lw ? 0 : 1)) }
                            GradientStop { position: 0.125; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * (sl.lw ? 0 : 0.5625)) }
                            GradientStop { position: 0.25; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * (sl.lw ? 0 : 0.25)) }
                            GradientStop { position: 0.375; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * (sl.lw ? 0 : 0.0625)) }
                            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: 0.625; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * (sl.lw ? 0.0625 : 0)) }
                            GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * (sl.lw ? 0.25 : 0)) }
                            GradientStop { position: 0.875; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * (sl.lw ? 0.5625 : 0)) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.th.depthShadeInner * (sl.lw ? 1 : 0)) }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: sl.rTop; topRightRadius: sl.rTop; bottomLeftRadius: sl.rBot; bottomRightRadius: sl.rBot
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * (sl.lw ? 1 : 0)) }
                            GradientStop { position: 0.125; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * (sl.lw ? 0.5625 : 0)) }
                            GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * (sl.lw ? 0.25 : 0)) }
                            GradientStop { position: 0.375; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * (sl.lw ? 0.0625 : 0)) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: 0.625; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * (sl.lw ? 0 : 0.0625)) }
                            GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * (sl.lw ? 0 : 0.25)) }
                            GradientStop { position: 0.875; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * (sl.lw ? 0 : 0.5625)) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, root.th.depthLightTop * (sl.lw ? 0 : 1)) }
                        }
                    }
                    // top light, continuous down the column (same 0.13 -> 0 over ~143 px as the bloom's petals)
                    Rectangle {
                        id: topLight
                        anchors.fill: parent
                        topLeftRadius: sl.rTop; topRightRadius: sl.rTop; bottomLeftRadius: sl.rBot; bottomRightRadius: sl.rBot
                        readonly property real y0: sl.rc.y - root.colLay.y
                        readonly property real a0: root.th.topLight.a * Math.max(0, 1 - y0 / 143)
                        readonly property real a1: root.th.topLight.a * Math.max(0, 1 - (y0 + sl.rc.h) / 143)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, topLight.a0) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, topLight.a1) }
                        }
                    }
                    // drag target: accent outline
                    Rectangle {
                        anchors.fill: parent; color: "transparent"
                        topLeftRadius: sl.rTop; topRightRadius: sl.rTop; bottomLeftRadius: sl.rBot; bottomRightRadius: sl.rBot
                        border.width: 1.6; border.color: Qt.rgba(root.th.accent.r, root.th.accent.g, root.th.accent.b, 0.95 * sl.drop)
                    }
                    // hover rim catch: white light on the centre-facing edge, brightest at the pointer
                    Rectangle {
                        id: rimBar
                        // stays on the slot's straight edge: clear of the rounded corners
                        readonly property real lo: Math.max(6, sl.rTop)
                        readonly property real hi: Math.max(lo + 0.002, sl.height - Math.max(6, sl.rBot))
                        readonly property real c: Math.max(lo, Math.min(hi, root.rimY - root.driftY - sl.y))
                        readonly property real span: Math.max(0.002, hi - lo)
                        readonly property real pp: (c - lo) / span
                        readonly property real rr: Math.max(0.002, root.th.rimCatchSpread * sl.height) / span
                        readonly property real a: root.th.rimCatchAlpha * sl.rim
                        width: root.th.rimCatchWidth; radius: width / 2
                        x: sl.lw ? root.th.rimCatchInset : parent.width - root.th.rimCatchInset - width
                        y: lo; height: span
                        gradient: Gradient {
                            GradientStop { position: Math.max(0, rimBar.pp - rimBar.rr);        color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: Math.max(0, rimBar.pp - rimBar.rr * 0.75); color: Qt.rgba(1, 1, 1, rimBar.a * 0.04) }
                            GradientStop { position: Math.max(0, rimBar.pp - rimBar.rr * 0.5);  color: Qt.rgba(1, 1, 1, rimBar.a * 0.25) }
                            GradientStop { position: Math.max(0, rimBar.pp - rimBar.rr * 0.25); color: Qt.rgba(1, 1, 1, rimBar.a * 0.65) }
                            GradientStop { position: rimBar.pp;                                 color: Qt.rgba(1, 1, 1, rimBar.a) }
                            GradientStop { position: Math.min(1, rimBar.pp + rimBar.rr * 0.25); color: Qt.rgba(1, 1, 1, rimBar.a * 0.65) }
                            GradientStop { position: Math.min(1, rimBar.pp + rimBar.rr * 0.5);  color: Qt.rgba(1, 1, 1, rimBar.a * 0.25) }
                            GradientStop { position: Math.min(1, rimBar.pp + rimBar.rr * 0.75); color: Qt.rgba(1, 1, 1, rimBar.a * 0.04) }
                            GradientStop { position: Math.min(1, rimBar.pp + rimBar.rr);        color: Qt.rgba(1, 1, 1, 0) }
                        }
                    }
                    // current workspace: accent tick on the centre-facing edge (bloom's tick constants, vertical)
                    Rectangle {
                        width: root.th.tickWidth; height: root.th.tickLen; radius: width / 2
                        x: (sl.lw ? root.th.colTickInset : parent.width - root.th.colTickInset) - width / 2
                        y: (parent.height - height) / 2
                        color: Qt.rgba(root.th.accent.r, root.th.accent.g, root.th.accent.b, root.th.tickAlpha * sl.cur)
                    }
                    // app watermark behind the label (hovered slot: label box is the unwidened slot)
                    AppMark {
                        x: (sl.lw ? sl.widen : 0) + sl.rc.w / 2 - width / 2; y: (sl.height - height) / 2
                        size: root.th.colWatermarkPx
                        fadeMs: root.th.watermarkFadeMs
                        cls: sl.wcls
                        opacity: root.th.watermarkAlpha + root.th.watermarkHoverAdd * sl.hov
                    }
                    // label: digit / gear (Settings). The current workspace marks its layout with Omarchy's glyph: small, in the
                    // text colour at colGlyphAlpha, above a slightly smaller number (see colGlyphPx / colPair*), so it reads as a quiet
                    // layout badge instead of a solid white block. Without a font that has the glyph: plain number (+ the accent tick).
                    Item {
                        id: colLabel
                        x: sl.lw ? sl.widen : 0; width: sl.rc.w; height: parent.height
                        scale: 1 - (1 - root.th.colPress) * sl.press
                        opacity: sl.special ? 0.85 + 0.15 * sl.hov : 1 - (1 - root.th.colEmptyAlpha) * sl.emp * (1 - sl.hov)
                        readonly property bool badge: root.glyphOk && sl.isCurrent && !sl.special
                        readonly property bool gear: sl.special
                        // number (hidden for the gear slot)
                        Text {
                            visible: !colLabel.gear
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: (parent.height - height) / 2 + 1 + (colLabel.badge ? root.th.colPairNumberDy : 0)
                            text: root.wsLabel(sl.wid); textFormat: Text.PlainText; color: Qt.rgba(0, 0, 0, 0.5)
                            font.family: root.th.font; font.pixelSize: colLabel.badge ? root.th.colPairNumberPx : root.th.colNumberPx; font.weight: Font.Medium
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            visible: !colLabel.gear
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: (parent.height - height) / 2 + (colLabel.badge ? root.th.colPairNumberDy : 0)
                            text: root.wsLabel(sl.wid); textFormat: Text.PlainText; color: root.th.text
                            font.family: root.th.font; font.pixelSize: colLabel.badge ? root.th.colPairNumberPx : root.th.colNumberPx; font.weight: Font.Medium
                            font.features: ({ "tnum": 1 })
                        }
                        // layout glyph badge above the number (current workspace)
                        Text {
                            visible: colLabel.badge
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: (parent.height - height) / 2 + root.th.colBadgeDy
                            text: root.modeGlyph(root.activeMode); textFormat: Text.PlainText; color: root.th.text; opacity: root.th.colGlyphAlpha
                            font.family: root.th.iconFont; font.pixelSize: root.th.colGlyphPx
                        }
                        // Settings gear
                        Text {
                            visible: colLabel.gear
                            anchors.centerIn: parent; anchors.verticalCenterOffset: 1
                            text: root.glyphOk ? root.th.glyphGear : "\u2699\ufe0e"; textFormat: Text.PlainText; color: Qt.rgba(0, 0, 0, 0.5)
                            font.family: root.th.iconFont; font.pixelSize: root.gearPx(root.th.colGearPx); font.weight: Font.Medium
                        }
                        Text {
                            visible: colLabel.gear
                            anchors.centerIn: parent
                            text: root.glyphOk ? root.th.glyphGear : "\u2699\ufe0e"; textFormat: Text.PlainText; color: root.th.text
                            font.family: root.th.iconFont; font.pixelSize: root.gearPx(root.th.colGearPx); font.weight: Font.Medium
                        }
                    }
                }
            }
        }

        // chips + rails of the revealed item (both layouts); origin = layout origin (+ drift)
        Item {
            id: chipLayer
            x: root.vert ? root.driftX : root.hx + root.driftX
            y: root.vert ? root.driftY : root.hy + root.driftY

            // chip rail of the revealed petal: one instance per petal, rising/retracting with its chips
            Repeater {
                id: railOwner
                // No current rail exists for an empty petal. The model is keyed
                // by petal so cached rows cannot survive a change of owner.
                model: !root.vert && root.revealed >= 0 && chipList.count > 0 ? [root.revealed] : []
                delegate: RailArc {
                    id: ownRail
                    th: root.th; live: true
                    rows: root.railRows
                    readonly property var pl: root.lay[root.revealed]
                    spawnA: pl ? pl.mid : (root.revealed >= 0 ? root.baseMid(root.revealed) : 0)
                    spawnR: pl ? pl.roH - root.th.chipSpawnInset : root.chipR0
                    property real riseTarget: 0
                    p: riseTarget
                    Behavior on p {
                        NumberAnimation { duration: root.fdur(root.chipsOpen ? root.th.chipRiseMs : root.th.chipFallMs); easing.type: root.chipsOpen ? Easing.OutCubic : Easing.InCubic }
                    }
                    Component.onCompleted: riseTarget = Qt.binding(() => root.chipsOpen ? 1 : 0)
                }
            }
            // retiring rails: keep-alive copies that retract into their petal with the retiring chips
            Repeater {
                model: railLeaveList
                delegate: RailArc {
                    id: lr
                    required property int uid
                    required property int petal
                    required property string rows_json
                    required property real startP
                    th: root.th
                    rows: JSON.parse(rows_json)
                    readonly property var pl: root.lay[petal]
                    spawnA: pl ? pl.mid : root.baseMid(petal)
                    spawnR: pl ? pl.roH - root.th.chipSpawnInset : root.chipR0
                    p: startP
                    NumberAnimation on p { from: lr.startP; to: 0; duration: root.fdur(Math.max(30, root.th.chipFallMs * lr.startP)); easing.type: Easing.InCubic
                        onFinished: Qt.callLater(() => root.dropRailLeaving(lr.uid)) }
                }
            }

            // vertical layout: chip band of the revealed slot, rising/retracting with its chips (one per slot)
            Repeater {
                id: vRailOwner
                model: root.vert && root.revealed >= 0 && chipList.count > 0 ? [root.revealed] : []
                delegate: RailRect {
                    th: root.th; live: true
                    rows: root.vRows
                    spawnX: root.vSpawn ? root.vSpawn.x : 0
                    spawnY: root.vSpawn ? root.vSpawn.y : 0
                    property real riseTarget: 0
                    p: riseTarget
                    Behavior on p {
                        NumberAnimation { duration: root.fdur(root.chipsOpen ? root.th.chipRiseMs : root.th.chipFallMs); easing.type: root.chipsOpen ? Easing.OutCubic : Easing.InCubic }
                    }
                    Component.onCompleted: riseTarget = Qt.binding(() => root.chipsOpen ? 1 : 0)
                }
            }
            Repeater {
                model: vRailLeaveList
                delegate: RailRect {
                    id: vlr
                    required property int uid
                    required property string rows_json
                    required property real spx
                    required property real spy
                    required property real startP
                    th: root.th
                    rows: JSON.parse(rows_json)
                    spawnX: vlr.spx; spawnY: vlr.spy
                    p: startP
                    NumberAnimation on p { from: vlr.startP; to: 0; duration: root.fdur(Math.max(30, root.th.chipFallMs * vlr.startP)); easing.type: Easing.InCubic
                        onFinished: Qt.callLater(() => root.dropVRailLeaving(vlr.uid)) }
                }
            }

            // window chips: each emerges from its own petal's outer edge and retracts back into it
            Repeater {
                id: chipRepeater
                model: chipList
                delegate: Item {
                    id: chip
                    required property int index
                    required property string address
                    required property string title
                    required property string cls
                    required property int ws
                    required property bool floating
                    required property bool fullscreen
                    required property bool grouped
                    readonly property bool hasSlot: !!root.slots[index]
                    readonly property var slot: root.slots[index] || ({ x: 0, y: 0, ang: 0, r: 0 })
                    // petal spawn point (polar, bloom-local): just inside the grown petal's outer edge
                    readonly property var pl: root.lay[root.revealed]
                    readonly property real spawnA: pl ? pl.mid : (root.revealed >= 0 ? root.baseMid(root.revealed) : 0)
                    readonly property real spawnR: pl ? pl.roH - root.th.chipSpawnInset : root.chipR0
                    // slot (polar); no position animation until the first real placement is done
                    property bool armed: false
                    onHasSlotChanged: Qt.callLater(() => { if (chip.hasSlot) chip.armed = true })
                    Component.onCompleted: {
                        riseTarget = Qt.binding(() => root.chipsOpen ? 1 : 0)
                        Qt.callLater(() => { if (chip.hasSlot) chip.armed = true })
                    }
                    property real sr: hasSlot ? slot.r : spawnR
                    property real sa: hasSlot ? slot.ang : spawnA
                    // vertical layout: slot + spawn point in column-local px
                    readonly property real spx: root.vSpawn ? root.vSpawn.x : 0
                    readonly property real spy: root.vSpawn ? root.vSpawn.y : 0
                    property real sx: hasSlot ? slot.x : spx
                    property real sy: hasSlot ? slot.y : spy
                    Behavior on sx { enabled: chip.armed && root.vert; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                    Behavior on sy { enabled: chip.armed && root.vert; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                    Behavior on sr { enabled: chip.armed; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                    Behavior on sa { enabled: chip.armed; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
                    property real riseTarget: 0
                    property real rise: riseTarget
                    Behavior on rise {
                        NumberAnimation { duration: root.fdur(root.chipsOpen ? root.th.chipRiseMs : root.th.chipFallMs); easing.type: root.chipsOpen ? Easing.OutCubic : Easing.InCubic }
                    }
                    readonly property real pr: Math.max(0, Math.min(1, rise))
                    readonly property real curA: spawnA + G.wrap(sa - spawnA) * pr
                    readonly property real curR: spawnR + (sr - spawnR) * pr
                    readonly property real wantX: root.vert ? spx + (sx - spx) * pr : curR * Math.cos(curA)
                    readonly property real wantY: root.vert ? spy + (sy - spy) * pr : curR * Math.sin(curA)
                    // screen clamp (chips never leave the display)
                    x: Math.max(8 + width / 2 - chipLayer.x, Math.min(root.sw - 8 - width / 2 - chipLayer.x, wantX)) - width / 2
                    y: Math.max(8 + height / 2 - chipLayer.y, Math.min(root.sh - 8 - height / 2 - chipLayer.y, wantY)) - height / 2
                    width: root.th.chipSize; height: root.th.chipSize
                    readonly property bool isHover: root.hoverChip === index
                    readonly property bool ghosted: address === root.dragAddr && (root.dragging || root.flying)
                    opacity: ghosted ? (root.flying ? 0 : 0.25) : pr
                    Behavior on opacity { enabled: chip.ghosted || root.dragging || root.flying; NumberAnimation { duration: root.dur(100) } }
                    property real hoverK: (isHover || (root.dragging && root.insIdx === index)) ? 1.14 : 1
                    Behavior on hoverK { NumberAnimation { duration: root.dur(root.th.hoverMs); easing.type: Easing.OutCubic } }
                    scale: (root.th.chipSpawnScale + (1 - root.th.chipSpawnScale) * pr) * hoverK
                    z: isHover ? 3 : 1

                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: Qt.rgba(root.th.glass.r + 0.02, root.th.glass.g + 0.02, root.th.glass.b + 0.03, root.th.chipAlpha)
                        border.width: 1; border.color: chip.isHover ? root.th.accent : Qt.rgba(1, 1, 1, 0.22)
                        Behavior on border.color { ColorAnimation { duration: root.dur(root.th.hoverMs) } }
                    }
                    // side-by-side insertion: the target half glows
                    Item {
                        anchors.fill: parent
                        opacity: root.dragging && root.insIdx === chip.index ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: root.dur(90) } }
                        Rectangle {
                            width: parent.width / 2; height: parent.height
                            x: root.insSide === "l" ? 0 : width
                            radius: 6
                            color: Qt.rgba(root.th.accent.r, root.th.accent.g, root.th.accent.b, 0.8)
                            Behavior on x { NumberAnimation { duration: root.dur(90); easing.type: Easing.OutCubic } }
                        }
                        Rectangle {
                            width: 4; height: parent.height + 14; radius: 2; y: -7
                            x: root.insSide === "l" ? -7 : parent.width + 3
                            color: root.th.accent
                            Behavior on x { NumberAnimation { duration: root.dur(90); easing.type: Easing.OutCubic } }
                        }
                    }
                    property var entry: { DesktopEntries.applications.values; return DesktopEntries.heuristicLookup(chip.cls) }
                    Image {
                        anchors.centerIn: parent; width: 22; height: 22; sourceSize: Qt.size(44, 44)
                        source: chip.entry && chip.entry.icon ? Quickshell.iconPath(chip.entry.icon, true) : ""
                        visible: source !== ""
                    }
                    Text {
                        anchors.centerIn: parent; visible: !chip.entry || !chip.entry.icon
                        text: String(chip.cls || "?").slice(0, 1).toUpperCase()
                        color: root.th.text; font.family: root.th.font; font.pixelSize: 15; font.weight: Font.DemiBold; textFormat: Text.PlainText
                    }
                    // title label
                    Rectangle {
                        id: lbl
                        readonly property real wantX: (chip.width - width) / 2
                        x: Math.max(8 - chipLayer.x - chip.x, Math.min(root.sw - 8 - chipLayer.x - chip.x - width, wantX))
                        y: -height - 8
                        width: Math.min(labelText.implicitWidth + 18, 300); height: 24; radius: 12
                        color: Qt.rgba(root.th.glass.r, root.th.glass.g, root.th.glass.b, 0.82)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                        opacity: chip.isHover ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: root.dur(root.th.hoverMs) } }
                        Text {
                            id: labelText
                            anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9
                            verticalAlignment: Text.AlignVCenter
                            text: chip.title; elide: Text.ElideRight; textFormat: Text.PlainText
                            color: root.th.text; font.family: root.th.font; font.pixelSize: root.th.labelPx
                        }
                    }
                }
            }

            // retiring chips: keep-alive copies that play the spawn in reverse into their petal, then vanish
            Repeater {
                model: leaveList
                delegate: Item {
                    id: lc
                    required property int uid
                    required property string cls
                    required property int petal
                    required property real sa
                    required property real sr
                    required property real sx
                    required property real sy
                    required property real spx
                    required property real spy
                    required property bool vert
                    required property real startP
                    property real p: startP
                    NumberAnimation on p { from: lc.startP; to: 0; duration: root.fdur(Math.max(30, root.th.chipFallMs * lc.startP)); easing.type: Easing.InCubic
                        onFinished: Qt.callLater(() => root.dropLeaving(lc.uid)) }
                    readonly property var pl: root.lay[petal]
                    readonly property real spawnA: pl ? pl.mid : root.baseMid(petal)
                    readonly property real spawnR: pl ? pl.roH - root.th.chipSpawnInset : root.chipR0
                    readonly property real curA: spawnA + G.wrap(sa - spawnA) * p
                    readonly property real curR: spawnR + (sr - spawnR) * p
                    width: root.th.chipSize; height: root.th.chipSize
                    x: Math.max(8 + width / 2 - chipLayer.x, Math.min(root.sw - 8 - width / 2 - chipLayer.x, vert ? spx + (sx - spx) * p : curR * Math.cos(curA))) - width / 2
                    y: Math.max(8 + height / 2 - chipLayer.y, Math.min(root.sh - 8 - height / 2 - chipLayer.y, vert ? spy + (sy - spy) * p : curR * Math.sin(curA))) - height / 2
                    opacity: p
                    scale: root.th.chipSpawnScale + (1 - root.th.chipSpawnScale) * p
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: Qt.rgba(root.th.glass.r + 0.02, root.th.glass.g + 0.02, root.th.glass.b + 0.03, root.th.chipAlpha)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
                    }
                    property var entry: { DesktopEntries.applications.values; return DesktopEntries.heuristicLookup(lc.cls) }
                    Image {
                        anchors.centerIn: parent; width: 22; height: 22; sourceSize: Qt.size(44, 44)
                        source: lc.entry && lc.entry.icon ? Quickshell.iconPath(lc.entry.icon, true) : ""
                        visible: source !== ""
                    }
                    Text {
                        anchors.centerIn: parent; visible: !lc.entry || !lc.entry.icon
                        text: String(lc.cls || "?").slice(0, 1).toUpperCase()
                        color: root.th.text; font.family: root.th.font; font.pixelSize: 15; font.weight: Font.DemiBold; textFormat: Text.PlainText
                    }
                }
            }
        }

        // dragged chip
        Rectangle {
            id: ghost
            visible: root.dragging || root.flying
            width: root.th.chipSize + 4; height: width; radius: width / 2
            x: root.gx - width / 2; y: root.gy - height / 2
            scale: root.dragging ? 1.12 : (0.7 + 0.3 * root.fadeGhost)
            opacity: root.fadeGhost
            color: Qt.rgba(root.th.glass.r + 0.03, root.th.glass.g + 0.03, root.th.glass.b + 0.04, 0.9)
            border.width: 1.5; border.color: root.th.accent
            Behavior on scale { NumberAnimation { duration: root.dur(120); easing.type: Easing.OutCubic } }
            property var entry: { DesktopEntries.applications.values; return root.dragWin ? DesktopEntries.heuristicLookup(root.dragWin.cls) : null }
            Image {
                anchors.centerIn: parent; width: 24; height: 24; sourceSize: Qt.size(48, 48)
                source: ghost.entry && ghost.entry.icon ? Quickshell.iconPath(ghost.entry.icon, true) : ""
                visible: source !== ""
            }
            Text {
                anchors.centerIn: parent; visible: !ghost.entry || !ghost.entry.icon
                text: root.dragWin ? String(root.dragWin.cls || "?").slice(0, 1).toUpperCase() : ""
                color: root.th.text; font.family: root.th.font; font.pixelSize: 16; textFormat: Text.PlainText
            }
        }


        // ------------------------------------------------------------ settings card
        // Click outside the card closes only the card; while it is open the switcher underneath ignores input.
        MouseArea {
            anchors.fill: parent
            enabled: root.settingsOpen
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: root.closeSettings()
        }
        Rectangle {
            id: card
            readonly property real w: cardRows.width + root.th.cardPad * 2
            readonly property real h: cardRows.height + root.th.cardPad * 2
            // origin: the Settings item. bloom = the petal's outer edge midpoint, card sits just beyond it along the
            // petal's axis; vertical = the slot's centre-facing side, card beside the column.
            readonly property point org: {
                const g = root.landingPoint(root.settingsIndex)
                return Qt.point(g.x, g.y)
            }
            readonly property var sp: root.lay[root.settingsIndex]
            // placement (Geometry.js cardPlace / ColumnGeometry.js cardPlace): bloom = adjacent to the ring (cardGap beyond
            // its outer edge incl. hover growth) at the on-screen angle nearest the gear petal; vertical = beside the column
            readonly property var place: root.vert
                ? CG.cardPlace(root.colLay, root.settingsIndex, w, h, root.th.cardGap, root.sw, root.sh, root.th.cardMargin)
                : G.cardPlace(root.hx + root.driftX, root.hy + root.driftY, (sp ? sp.roH : root.th.outerR * root.ringK + root.th.hoverGrow), sp ? sp.mid : -Math.PI / 2,
                              w, h, root.th.cardGap, root.sw, root.sh, root.th.cardMargin)
            x: place.x
            y: place.y
            Behavior on x { enabled: root.settingsK > 0.02; NumberAnimation { duration: root.dur(220); easing.type: Easing.OutCubic } }
            Behavior on y { enabled: root.settingsK > 0.02; NumberAnimation { duration: root.dur(220); easing.type: Easing.OutCubic } }
            width: w; height: h; radius: root.th.cardRadius
            visible: root.settingsK > 0.004
            opacity: root.settingsK
            color: Qt.rgba(root.th.glass.r + 0.02, root.th.glass.g + 0.02, root.th.glass.b + 0.03, root.th.cardAlpha)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20)
            transform: Scale {
                origin.x: card.org.x - card.x; origin.y: card.org.y - card.y
                xScale: root.th.cardScale0 + (1 - root.th.cardScale0) * root.settingsK
                yScale: xScale
            }
            // swallow clicks on the card background
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
            TextMetrics { id: labelMetrics; text: "Layout"; font.family: root.th.font; font.pixelSize: root.th.cardLabelPx; font.weight: Font.Medium }
            Column {
                id: cardRows
                x: root.th.cardPad; y: root.th.cardPad
                spacing: root.th.cardRowGap
                // one segmented row per setting (same delegate for both)
                Repeater {
                    model: [
                        { key: "layout", label: "Layout", opts: [{ name: "bloom", label: "Bloom" }, { name: "vertical", label: "Vertical" }] },
                        { key: "theme", label: "Theme", opts: [{ name: "neutral", label: "Neutral" }, { name: "omarchy", label: "Omarchy" }] }
                    ]
                    delegate: Row {
                        id: setRow
                        required property var modelData
                        readonly property string cur: modelData.key === "layout" ? root.layoutMode : root.themeMode
                        height: root.th.cardRow
                        spacing: 14
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: labelMetrics.width
                            text: setRow.modelData.label; textFormat: Text.PlainText
                            color: root.th.text; opacity: 0.85
                            font.family: root.th.font; font.pixelSize: root.th.cardLabelPx; font.weight: Font.Medium
                        }
                        // segmented control
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.th.segW * 2 + 4; height: 24
                            Rectangle { anchors.fill: parent; radius: 8; color: Qt.rgba(0, 0, 0, 0.22) }
                            Rectangle {
                                y: 2; height: parent.height - 4; width: root.th.segW; radius: 6
                                x: 2 + (setRow.cur === setRow.modelData.opts[1].name ? root.th.segW : 0)
                                color: Qt.rgba(1, 1, 1, root.th.pillAlpha)
                                Behavior on x { NumberAnimation { duration: root.dur(root.th.segMs); easing.type: Easing.OutCubic } }
                            }
                            Repeater {
                                model: setRow.modelData.opts
                                delegate: Item {
                                    required property int index
                                    required property var modelData
                                    x: 2 + index * root.th.segW; width: root.th.segW; height: parent.height
                                    readonly property bool on: setRow.cur === modelData.name
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.label; textFormat: Text.PlainText
                                        color: root.th.text; opacity: parent.on ? 1 : (segMouse.containsMouse ? 0.85 : 0.6)
                                        font.family: root.th.font; font.pixelSize: root.th.segPx; font.weight: Font.Medium
                                        Behavior on opacity { NumberAnimation { duration: root.dur(120) } }
                                    }
                                    MouseArea {
                                        id: segMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        onClicked: setRow.modelData.key === "layout" ? root.setLayout(parent.modelData.name) : root.setTheme(parent.modelData.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Behavior on height { NumberAnimation { duration: root.dur(160); easing.type: Easing.OutCubic } }
        }

        // toast
        Rectangle {
            id: toastPill
            readonly property real wantY: root.vert ? (root.colLay.y + root.colLay.height + 14 + height <= root.sh - 12 ? root.colLay.y + root.colLay.height + 14 : root.colLay.y - 14 - height)
                                                    : (root.hy < root.sh - 260 ? root.hy + 230 : root.hy - 230 - height)
            x: Math.max(12, Math.min(root.sw - width - 12, root.vigX - width / 2))
            y: Math.max(12, Math.min(root.sh - height - 12, wantY)) + (root.toastShown ? 0 : 8)
            width: toastLabel.implicitWidth + 28; height: 30; radius: 15
            color: Qt.rgba(root.th.glass.r, root.th.glass.g, root.th.glass.b, 0.82)
            border.width: 1; border.color: Qt.rgba(root.th.accent.r, root.th.accent.g, root.th.accent.b, 0.8)
            opacity: root.toastShown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: root.dur(140) } }
            Behavior on y { NumberAnimation { duration: root.dur(160); easing.type: Easing.OutCubic } }
            Text {
                id: toastLabel
                anchors.centerIn: parent
                text: root.toastText; textFormat: Text.PlainText
                color: root.th.text; font.family: root.th.font; font.pixelSize: root.th.labelPx + 1
            }
        }
    }
}
