# Changelog

## 1.1.0 - Polish

- Glyphs: the layout glyphs and the gear are drawn in a font that fontconfig confirms has them (the shell's own family first, else an installed Nerd Font). With no such font, the current vertical slot shows its number and accent tick, and the gear a plain symbol, instead of a missing-glyph box.
- Vertical: removed the 1 px light line on the centre-facing edge of every slot; the rim catch stays on the slot's straight edge, clear of the rounded corners.
- App watermark: masked with a soft radial feather, so the app icon's own tile no longer shows as a gray square (still grayscale, same alpha).
- Seams: the 2 px gaps between petals, slots and around the center well are filled with a near-black (alpha above the blur threshold), so they frost with the glass and read as glass seams over bright wallpaper.
- Center well: frosted like the rest (fill alpha above `ignore_alpha`), lighter than the petals, with the inner shadow and lower lip kept.
- Settings card: attaches to the gear with a constant `cardGap`. Bloom places it on the gear petal's outward axis, mirrors or fans around the ring if that would leave the screen, and never overlaps the ring. Vertical places it beside the gear slot, on the other side of the column if there is no room.
- Reduced motion: follows Omarchy's `Style.reduceMotion`; all durations go through one function, open/close become a short fade. `status` reports `reducedMotion`.
- Tests: seam paths, card placement (bloom and vertical).

## 1.0.0

- First public release.
- Bloom (radial) and Vertical layouts, one global setting.
- Settings petal/slot with Layout (Bloom | Vertical) and Theme (Neutral | Omarchy).
- Drag a window chip to another workspace; drop on another chip to place side by side.
- IPC: `toggle`, `status`, `layout`, `theme`.
