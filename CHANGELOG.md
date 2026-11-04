# Changelog

## 1.1.0 - Polish

- Bloom is never clipped: the ring is always a complete circle. The hub slides inward from the pointer just far enough that the whole bloom (well, every petal, hover growth, dial drift) stays inside the 8 px screen margin. The old edge fan / flip / 1.7x scale-up that produced partial rings is gone (the ring still scales for more than 14 workspaces). Hit-testing follows the hub.
- The ring never rotates: workspace 1 is always at 12 o'clock and the Settings gear is always the last slot, in every corner, edge and the centre (fixed positions for muscle memory).
- Settings card (bloom): placed adjacent to the ring, `cardGap` (10 px) beyond its outer edge including hover growth, at the fully on-screen angle closest to the gear petal (equal angles: the side nearer the screen centre). It never overlaps the ring. While the card is open the gear stays in its hovered state (grown, rim catch lit) in both layouts, so the card reads as belonging to it. Vertical: beside the gear slot on the centre side (other side if it cannot fit).
- Vertical: the current workspace shows Omarchy's layout glyph as a small badge (10 px, text colour at 0.85) above a 14 px number, instead of a big white glyph.
- Well: soft dimple again. The dark ring is gone (the fill runs out to the petals), the inner shadow is a thin crescent at the upper rim only (alpha 0.20, starts at 74 %), slightly lighter fill (#7a7a7a at 0.22): frosted and quiet over busy wallpapers.
- Seams: 0.32 alpha (was 0.38). A hovered or pulsing petal's seam stops at its neighbours' resting outer edge, so it no longer leaves a dark stub.
- Fallback gear (no Nerd Font) is drawn 1.7x larger in both layouts, so it matches the cog.
- Reduced motion: chips, bands and the settings card use a 90 ms fade instead of appearing instantly.
- Glyphs: the layout glyphs and the gear are drawn in a font that fontconfig confirms has them (the shell's own family first, else an installed Nerd Font). With no such font, the current vertical slot shows its number and accent tick, and the gear a plain symbol, instead of a missing-glyph box.
- Current-workspace accent tick moved 1.5 px further in (6 px) in both layouts, so the hover rim catch no longer touches it; the vertical tick stays vertically centred on the slot, clear of the layout badge.
- Vertical: removed the 1 px light line on the centre-facing edge of every slot; the rim catch stays on the slot's straight edge, clear of the rounded corners.
- App watermark: masked with a soft radial feather, so the app icon's own tile no longer shows as a gray square (still grayscale, same alpha).
- Reduced motion follows Omarchy's `Style.reduceMotion`; all durations go through one function. `status` reports `reducedMotion`.
- Tests: bloom stays on screen for every pointer position (dense sweep and all corners/edges), fixed ring orientation and the card placement (on screen, clear of the ring incl. hover growth, nearest the gear), seam paths, vertical card (including the mirrored side).

## 1.0.0

- First public release.
- Bloom (radial) and Vertical layouts, one global setting.
- Settings petal/slot with Layout (Bloom | Vertical) and Theme (Neutral | Omarchy).
- Drag a window chip to another workspace; drop on another chip to place side by side.
- IPC: `toggle`, `status`, `layout`, `theme`.
