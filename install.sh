#!/usr/bin/env bash
# Install the Window Sticker omarchy shell plugin.
set -euo pipefail

ID="io.github.hjanuschka.window-sticker"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUG_DIR="$HOME/.config/omarchy/plugins/$ID"
BIND="$HOME/.config/hypr/bindings.lua"

mkdir -p "$HOME/.config/omarchy/plugins"
ln -sfn "$SRC" "$PLUG_DIR"
echo "linked $PLUG_DIR -> $SRC"

# Enable in shell.json (idempotent).
python3 - "$ID" <<'PY'
import json, os, sys
pid = sys.argv[1]
p = os.path.expanduser("~/.config/omarchy/shell.json")
with open(p) as f:
    cfg = json.load(f)
plugins = cfg.setdefault("plugins", [])
if not any(pl.get("id") == pid for pl in plugins):
    plugins.append({"id": pid})
    with open(p, "w") as f:
        json.dump(cfg, f, indent=2)
    print("enabled in shell.json")
else:
    print("already enabled in shell.json")
PY

# Hyprland: click-through rule for the ribbon layer + keybinding (idempotent).
if ! grep -q "omarchy-window-sticker" "$BIND" 2>/dev/null; then
  cat >> "$BIND" <<'LUA'

-- Window sticker: ribbon overlays follow their windows without layer animations.
hl.layer_rule({ match = { namespace = "^omarchy-window-sticker$" }, no_anim = true })
o.bind("SUPER + SHIFT + R", "Window sticker", "omarchy-shell shell summon io.github.hjanuschka.window-sticker '{}'")
LUA
  echo "added layer rule + SUPER SHIFT+R binding to $BIND"
else
  echo "layer rule + binding already present"
fi

hyprctl reload >/dev/null 2>&1 || true
echo "--- hyprland config errors:"
hyprctl configerrors 2>&1 | sed 's/^/    /'
echo "--- layerrules:"
hyprctl layerrules 2>/dev/null | grep -A3 "window-sticker" | sed 's/^/    /' || echo "    (none yet)"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "done. Focus a window and press Super+Shift+R"
