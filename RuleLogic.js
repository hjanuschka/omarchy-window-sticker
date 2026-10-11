.pragma library

// Rule = { classMode, classText, classRe, titleMode, titleText, titleRe,
//          text, color, style, corner, glow, enabled }
// classRe/titleRe are the compiled patterns used for matching; the
// mode/text pairs only exist so the editor can round-trip what was typed.
// Rules saved before modes existed carry only classRe/titleRe and are
// edited in "regex" mode.

var MODES = ["exact", "contains", "starts", "regex"]

function escapeRe(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function compile(mode, text) {
  var t = String(text || "").trim()
  if (!t) return ""
  if (mode === "exact") return "^" + escapeRe(t) + "$"
  if (mode === "starts") return "^" + escapeRe(t)
  if (mode === "contains") return escapeRe(t)
  return t
}

// Empty string when valid, otherwise the engine's error message.
function validate(re) {
  if (!re) return ""
  try {
    new RegExp(re, "i")
    return ""
  } catch (e) {
    return String(e.message || e)
  }
}

function classOf(c) {
  if (!c) return ""
  if (c.class && typeof c.class === "object")
    return String(c.class.initial || c.class.class || "")
  return String(c.class || "")
}

function isSystemWindow(c) {
  return /screensaver|hyprlock|lockscreen|slock/i.test(classOf(c))
}

function matches(rule, c) {
  if (!rule || !c || rule.enabled === false) return false
  if (!rule.classRe && !rule.titleRe) return false
  try {
    if (rule.classRe && !new RegExp(rule.classRe, "i").test(classOf(c))) return false
    if (rule.titleRe && !new RegExp(rule.titleRe, "i").test(String(c.title || ""))) return false
    return true
  } catch (e) {
    return false
  }
}

function fieldOf(rule, field) {
  var mode = rule[field + "Mode"]
  var text = rule[field + "Text"]
  if (mode && text !== undefined) return { mode: mode, text: String(text) }
  var re = rule[field + "Re"] || ""
  return { mode: re ? "regex" : (field === "class" ? "exact" : "contains"), text: re }
}

var MODE_WORDS = { exact: "is", contains: "has", starts: "starts with", regex: "~" }

function describe(rule) {
  var parts = []
  var cf = fieldOf(rule, "class")
  var tf = fieldOf(rule, "title")
  if (cf.text) parts.push("app " + MODE_WORDS[cf.mode] + " " + cf.text)
  if (tf.text) parts.push("title " + MODE_WORDS[tf.mode] + " " + tf.text)
  return parts.length ? parts.join(" \u00b7 ") : "matches nothing"
}

// Candidate match criteria derived from one window, most specific first.
function suggestions(c) {
  if (!c) return []
  var out = []
  var seen = {}
  function add(field, mode, text, label) {
    text = String(text || "").trim()
    if (text.length < 2) return
    var key = field + "|" + mode + "|" + text.toLowerCase()
    if (seen[key]) return
    seen[key] = true
    out.push({ field: field, mode: mode, text: text, label: label })
  }

  var cls = classOf(c)
  if (cls) {
    add("class", "exact", cls, "app is " + cls)
    var toks = cls.split(/[.\-_]+/).filter(function(t) { return t.length >= 4 })
    if (toks.length > 1) {
      var longest = toks.reduce(function(a, b) { return b.length > a.length ? b : a })
      add("class", "contains", longest, "app has " + longest)
    }
  }

  var title = String(c.title || "")
  var pm = title.match(/(?:^|\s)(~?\/[^\s:'"]+)/)
  if (pm) {
    var segs = pm[1].replace(/\/+$/, "").split("/").filter(function(s) { return s && s !== "~" })
    if (segs.length) add("title", "contains", segs[segs.length - 1], "folder " + segs[segs.length - 1])
    if (segs.length >= 2) {
      var tail = segs.slice(-2).join("/")
      add("title", "contains", tail, "path \u2026/" + tail)
    }
  } else {
    var rm = title.match(/\b[\w.-]+\/([\w.-]{3,})\b/)
    if (rm) add("title", "contains", rm[1], "repo " + rm[1])
    var dm = title.match(/\b(?:[a-z0-9-]+\.)+[a-z]{2,}\b/i)
    if (dm && !/\.(md|txt|js|ts|qml|py|rs|go|c|cc|h|json)$/i.test(dm[0]))
      add("title", "contains", dm[0], "site " + dm[0])
  }

  // "doc - project - App" / "x | y" / "x \u00b7 y": the last segment is
  // usually the app name, the others are what identifies the window.
  var segsT = title.split(/\s+[-\u2013\u2014|\u00b7]\s+/)
    .map(function(s) { return s.replace(/^\(\d+\)\s*/, "").trim() })
    .filter(function(s) { return s.length >= 3 && s.length <= 40 })
  if (segsT.length > 1) {
    for (var i = 0; i < segsT.length - 1; i++)
      add("title", "contains", segsT[i], "title has \u201c" + segsT[i] + "\u201d")
  }

  return out.slice(0, 7)
}

// What a rule placed at `index` would do to the open windows. Rules before
// `index` win (first match), explicit stickers win over every rule.
function analyze(rule, index, rules, clients, stickers) {
  var res = { windows: [], matched: 0, applies: 0, explicit: 0, shadowed: 0, total: 0 }
  if (!rule) return res
  for (var i = 0; i < clients.length; i++) {
    var c = clients[i]
    if (isSystemWindow(c)) continue
    res.total++
    if (!matches(rule, c)) continue
    var status = "applies"
    var by = -1
    if (stickers && stickers[c.address]) {
      status = "explicit"
    } else {
      for (var j = 0; j < rules.length && j < index; j++) {
        if (matches(rules[j], c)) { status = "shadowed"; by = j; break }
      }
    }
    res.matched++
    res[status]++
    res.windows.push({ address: c.address, cls: classOf(c), title: String(c.title || ""), status: status, by: by })
  }
  return res
}
