#!/usr/bin/env bash
# Undo install.sh: drop the keybinding/layer rule and disable the plugin.
# Remove the plugin files afterwards with: omarchy plugin remove io.github.hjanuschka.window-sticker
set -euo pipefail

ID="io.github.hjanuschka.window-sticker"
BIND="$HOME/.config/hypr/bindings.lua"

if grep -qi "window[ -]sticker" "$BIND" 2>/dev/null; then
  cp "$BIND" "$BIND.bak.$(date +%s)"
  sed -i '/[Ww]indow[ -][Ss]ticker/d' "$BIND"
  hyprctl reload >/dev/null 2>&1 || true
  echo "removed Super+Shift+R from $BIND (backup kept)"
fi

omarchy plugin disable "$ID" >/dev/null 2>&1 && echo "disabled $ID" || true
echo "Stickers and rules are kept in ~/.local/state/omarchy-window-sticker (delete to reset)."
