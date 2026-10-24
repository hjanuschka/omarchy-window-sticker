.pragma library

// Which parts of a sticker are hidden behind other windows. Works on
// `hyprctl clients -j` objects plus a monitor table keyed by monitor id:
//   { activeWs, specialWs }
// Hyprland draws, per monitor: tiled < floating < pinned < fullscreen,
// and the shown special workspace above all of that. Within the same
// band the more recently focused window is on top.

function isVisible(c, mon) {
  if (!c || !mon || c.hidden === true || c.hidden === 1) return false
  var ws = c.workspace ? String(c.workspace.name || "") : ""
  return ws === mon.activeWs || (ws !== "" && ws === mon.specialWs)
    || c.pinned === true || c.pinned === 1
}

function rank(c, mon) {
  var ws = c.workspace ? String(c.workspace.name || "") : ""
  var band = c.fullscreen === 2 ? 4
    : (c.pinned === true || c.pinned === 1) ? 3
    : (c.floating === true || c.floating === 1) ? 2 : 1
  return (ws !== "" && ws === mon.specialWs ? 10 : 0) + band
}

function isAbove(o, t, mon) {
  var ro = rank(o, mon), rt = rank(t, mon)
  if (ro !== rt) return ro > rt
  return (o.focusHistoryID | 0) < (t.focusHistoryID | 0)
}

// box: sticker square in global coordinates. pad: window border width,
// drawn outside at/size. Returns { full, holes } with holes in box-local
// coordinates.
function occlusion(target, clients, monitors, box, pad) {
  var res = { full: false, holes: [] }
  var monId = String(target.monitor)
  var mon = monitors[monId]
  if (!mon) return res
  pad = pad || 0
  for (var i = 0; i < clients.length; i++) {
    var o = clients[i]
    if (o.address === target.address || String(o.monitor) !== monId) continue
    if (!isVisible(o, mon) || !isAbove(o, target, mon)) continue
    var at = o.at || [0, 0], sz = o.size || [0, 0]
    var x1 = Math.max(box.x, at[0] - pad), y1 = Math.max(box.y, at[1] - pad)
    var x2 = Math.min(box.x + box.w, at[0] + sz[0] + pad)
    var y2 = Math.min(box.y + box.h, at[1] + sz[1] + pad)
    if (x2 <= x1 || y2 <= y1) continue
    if (x1 === box.x && y1 === box.y && x2 === box.x + box.w && y2 === box.y + box.h) {
      res.full = true
      res.holes = []
      return res
    }
    res.holes.push({ x: x1 - box.x, y: y1 - box.y, w: x2 - x1, h: y2 - y1 })
  }
  return res
}
