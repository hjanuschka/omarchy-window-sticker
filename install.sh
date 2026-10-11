#!/usr/bin/env bash
# Set up Window Sticker: enable the plugin and bind Super+Shift+R.
# Works both from a dev checkout (links it into the plugins dir) and from
# a copy installed with `omarchy plugin add`.
set -euo pipefail

ID="io.github.hjanuschka.window-sticker"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUG_DIR="$HOME/.config/omarchy/plugins/$ID"
BIND="$HOME/.config/hypr/bindings.lua"

if [[ "$(realpath "$SRC")" != "$(realpath -m "$PLUG_DIR")" ]]; then
  mkdir -p "$(dirname "$PLUG_DIR")"
  ln -sfn "$SRC" "$PLUG_DIR"
  echo "linked $PLUG_DIR -> $SRC"
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
if ! jq -e --arg id "$ID" '(.plugins // []) | any(.id == $id)' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
  omarchy plugin enable "$ID" >/dev/null && echo "enabled $ID"
fi

if ! grep -q "omarchy-window-sticker" "$BIND" 2>/dev/null; then
  cat >> "$BIND" <<'LUA'

-- Window sticker: ribbon overlays follow their windows without layer animations.
hl.layer_rule({ match = { namespace = "^omarchy-window-sticker$" }, no_anim = true })
o.bind("SUPER + SHIFT + R", "Window sticker", "omarchy-shell shell summon io.github.hjanuschka.window-sticker '{}'")
LUA
  echo "added Super+Shift+R to $BIND"
fi

hyprctl reload >/dev/null 2>&1 || true
errors=$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true)
[[ -n $errors ]] && printf 'Hyprland config errors:\n%s\n' "$errors"
echo "done. Focus a window and press Super+Shift+R"
