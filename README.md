# Window Sticker

Book-ribbon project labels pinned to window corners on Omarchy.

Focus a window, hit **Super+Shift+R**, type a label ("Project X"), Enter --
a ribbon hangs from the window's top-right corner. It follows the window
around, hides when the window is minimized / on another workspace /
fullscreen, and disappears when the window closes.

## Usage

| Action | How |
|---|---|
| Add / edit sticker | `Super+Shift+R`, type label, `Enter` |
| Remove sticker | `Super+Shift+R` on a stickered window, click **Remove** |
| Cancel | `Esc` |

Re-applying the shortcut on a window that already has a sticker opens the
picker with the current text prefilled.

## How it works

- Omarchy shell plugin (`keepLoaded` overlay). The picker captures the
  focused window via `hyprctl activewindow` before it takes keyboard
  focus.
- Each sticker is its own small layer surface
  (`omarchy-window-sticker` namespace) pinned to the target window's
  top-right corner; only the ribbon rectangle itself is ever covered.
- A 120 ms sync loop (plus Hyprland `rawEvent` wakeups) re-reads
  `hyprctl clients/monitors` and moves/hides ribbons. The loop only runs
  while at least one sticker exists.
- Stickers persist in `~/.local/state/omarchy-window-sticker/stickers.json`
  keyed by window address, so they survive shell restarts within a
  Hyprland session. Closing a window removes its sticker.

## Install

```bash
./install.sh
```

Links the plugin into `~/.config/omarchy/plugins/`, enables it in
`shell.json`, and adds the keybinding + layer rule to
`~/.config/hypr/bindings.lua`. Idempotent.

## CLI

```bash
# remove all stickers
omarchy-shell shell call io.github.hjanuschka.window-sticker clearAll '{}'
```

## Uninstall

```bash
rm ~/.config/omarchy/plugins/io.github.hjanuschka.window-sticker
# remove the "Window sticker" lines from ~/.config/hypr/bindings.lua and
# the plugin entry from ~/.config/omarchy/shell.json, then:
omarchy restart shell
rm -r ~/.local/state/omarchy-window-sticker
```
