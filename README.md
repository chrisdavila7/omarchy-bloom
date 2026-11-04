# Bloom

A mouse-first workspace switcher for the Omarchy shell. Open it at the cursor, hover a workspace to see its windows, click to switch, or drag a window onto another workspace to move it.

![Bloom preview](preview.png)

## Features

- Two layouts: **Bloom** (radial) and **Vertical** (column).
- Hover a workspace to reveal its windows.
- Click a workspace to switch to it.
- Drag a window icon onto another workspace to move it silently. Hold **Shift** when you release to move it and follow it.
- Drop a window icon onto another window to place it side by side (dwindle workspaces; otherwise it is simply moved there).
- A Settings petal/slot (gear) with **Layout** (Bloom / Vertical) and **Theme** (Neutral / Omarchy).
- Never takes keyboard focus.

## Requirements

- Omarchy with its Quickshell shell.
- Hyprland 0.55 or newer with a **Lua** config. Bloom dispatches through Hyprland's Lua API (`hyprctl eval`), so it does not work with hyprlang configs.
- `python3`, only for side-by-side placement.
- Omarchy's workspace layout state (`~/.local/state/omarchy/workspace-layouts`) and its `o.workspace_mode` helper, used for side-by-side placement and the layout glyphs.

## Install

```sh
omarchy plugin add https://github.com/chrisdavila7/omarchy-bloom --enable
```

Bloom never edits your config. The steps below are optional and yours to add.

### Trigger (keybinding and/or gesture)

In `~/.config/hypr/bindings.lua`:

```lua
-- Keybinding (pick your own keys)
o.bind("SUPER + mouse:274", "Bloom", "omarchy-shell io.github.chrisdavila7.bloom toggle")

-- 3-finger swipe up
hl.gesture({
  fingers = 3,
  direction = "up",
  action = function() hl.exec_cmd("omarchy-shell io.github.chrisdavila7.bloom toggle") end,
})
```

`bin/bloom-toggle` runs the same command if you prefer a script path.

### Blur (optional)

In `~/.config/hypr/looknfeel.lua`:

```lua
hl.layer_rule({ match = { namespace = "^bloom$" }, blur = true, ignore_alpha = 0.2, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "^bloom-veil$" }, no_anim = true, animation = "none" })
```

Bloom works without these but looks flatter. Apply changes with `hyprctl reload`.

## Usage

Trigger Bloom with your binding or gesture (or `omarchy-shell io.github.chrisdavila7.bloom toggle`). It opens at the cursor. Hover, click, or drag as described above; toggle again to close.

### IPC

Run as `omarchy-shell io.github.chrisdavila7.bloom <function> [arg]`.

| Function | Argument | Result |
| --- | --- | --- |
| `toggle` | none | Open or close Bloom. |
| `layout` | `bloom` or `vertical` | Set the layout; returns the new value, or an error string. |
| `theme` | `neutral` or `omarchy` | Set the theme; returns the new value, or an error string. |
| `status` | none | JSON: `open`, `shown`, `pending`, `layout`, `theme`. |

## Settings

Stored in `~/.local/state/bloom/settings.json`:

```json
{ "layout": "bloom", "theme": "omarchy" }
```

`layout` is `bloom` or `vertical`; `theme` is `neutral` or `omarchy`. Defaults are `bloom` and `omarchy`. Change them from the gear or over IPC.

## Removal

```sh
omarchy plugin remove io.github.chrisdavila7.bloom
```

Then delete the bind, gesture and layer rules you added, run `hyprctl reload`, and remove saved settings:

```sh
rm -rf ~/.local/state/bloom
```

## Dependencies and licenses

- Bloom's code: MIT (see `LICENSE`).
- Bundles the Inter font under the SIL Open Font License 1.1 (`assets/fonts/INTER-OFL.txt`).
- Runtime: Quickshell (via Omarchy), Hyprland, `hyprctl`, `python3`.

## Known limitations

- No keyboard navigation.
- No reduced-motion support yet.
- Workspaces 1–5 are always shown.
- Multi-monitor setups and display scales other than 1.5 are untested.

## Development

```sh
node tests/test_geometry.js
node tests/test_column_geometry.js
python3 -m unittest discover tests
/usr/share/omarchy/bin/omarchy-plugin-validate .
```
