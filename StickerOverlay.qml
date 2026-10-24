import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import QtQuick.Effects
import "RuleLogic.js" as RL
import "Stacking.js" as Stacking

// Sticker overlays for Hyprland windows. Each sticker is a small layer
// surface pinned to one corner of its target window and rendered by
// StickerArt. The picker (Super+Shift+R) grabs the focused window before
// taking keyboard focus and offers presets, color, style, corner, emoji,
// glow, a live preview, an overview of stickered windows, and a rules
// editor for auto-stickering by class/title.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property real cornerSize: 110
  readonly property int syncInterval: 120

  readonly property var palette: [
    "accent", "#e5484d", "#f76b15", "#ffb224", "#30a46c", "#12a594",
    "#0091ff", "#5b5bd6", "#8e4ec6", "#d6409f", "#88909b"
  ]
  readonly property var cornerModel: [
    { id: "tl", label: "Top left" },
    { id: "tr", label: "Top right" },
    { id: "bl", label: "Bottom left" },
    { id: "br", label: "Bottom right" }
  ]
  readonly property var styleModel: [
    { id: "banner", label: "Banner" },
    { id: "flag", label: "Flag" },
    { id: "seal", label: "Seal" },
    { id: "tape", label: "Tape" },
    { id: "tag", label: "Tag" }
  ]
  readonly property var emojiList: [
    "\uD83D\uDD25", "\u2B50", "\uD83D\uDD12", "\u26A0\uFE0F",
    "\uD83D\uDE80", "\u2705", "\u274C", "\uD83D\uDC1B",
    "\uD83D\uDD27", "\uD83D\uDCCC"
  ]
  readonly property var presets: [
    { label: "PROD",    text: "PROD",         color: "#e5484d", style: "seal",   corner: "tr" },
    { label: "DRAFT",   text: "DRAFT",        color: "#ffb224", style: "tape",   corner: "tr" },
    { label: "WIP",     text: "WIP",          color: "#f76b15", style: "flag",   corner: "tl" },
    { label: "TODO",    text: "TODO",         color: "#0091ff", style: "banner", corner: "tr" },
    { label: "KEEP",    text: "DO NOT CLOSE", color: "#e5484d", style: "seal",   corner: "bl" },
    { label: "REVIEW",  text: "REVIEW",       color: "#8e4ec6", style: "tag",    corner: "br" }
  ]

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-window-sticker"
  readonly property string stateFile: stateDir + "/stickers.json"
  readonly property string rulesFile: stateDir + "/rules.json"

  // address -> { text, color, corner, style, glow }
  property var stickers: ({})
  // [{ classRe, titleRe, text, color, corner, style, glow }]
  property var rules: []
  // Last snapshot of clients used by overview/rules.
  property var lastClients: []

  // address -> PanelWindow
  property var ribbonWins: ({})

  // Picker state.
  property bool pickerVisible: false
  property string targetAddr: ""
  property string targetClass: ""
  property string targetLabel: ""
  property string targetMonitor: ""
  property bool emojiOpen: false
  property var targetClient: null

  // Composer selection.
  property string selectedColor: "accent"
  property string selectedCorner: "tr"
  property string selectedStyle: "banner"
  property bool selectedGlow: false

  function resolveColor(c) {
    return c === "accent" ? String(Color.accent) : c
  }

  property int borderSize: 0

  Process {
    running: true
    command: ["hyprctl", "getoption", "general:border_size", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.borderSize = JSON.parse(text).int || 0 } catch (e) {}
      }
    }
  }

  Component.onCompleted: {
    stickerLoader.running = true
    rulesLoader.running = true
  }

  // ---------------------------------------------------------- persistence

  Process {
    id: stickerLoader
    command: ["cat", root.stateFile]
    stdout: StdioCollector {
      onStreamFinished: {
        var txt = text.trim()
        if (txt) {
          try {
            var obj = JSON.parse(txt)
            if (obj && typeof obj === "object") root.stickers = obj
          } catch (e) {
            console.warn("window-sticker: unreadable stickers.json")
          }
        }
        Qt.callLater(function() { syncProc.running = true })
      }
    }
  }

  Process {
    id: rulesLoader
    command: ["cat", root.rulesFile]
    stdout: StdioCollector {
      onStreamFinished: {
        var txt = text.trim()
        if (txt) {
          try {
            var arr = JSON.parse(txt)
            if (Array.isArray(arr)) root.rules = arr
          } catch (e) {
            console.warn("window-sticker: unreadable rules.json")
          }
        }
      }
    }
  }

  Process { id: stickerSaver }
  Process { id: rulesSaver }

  function writeJson(proc, file, data) {
    proc.command = ["sh", "-c", "mkdir -p '" + root.stateDir + "' && printf %s '"
      + Qt.btoa(JSON.stringify(data)) + "' | base64 -d > '" + file + "'"]
    proc.running = true
  }

  function saveStickers() { writeJson(stickerSaver, root.stateFile, root.stickers) }
  function saveRules() { writeJson(rulesSaver, root.rulesFile, root.rules) }

  // ---------------------------------------------------------- tracking

  Process {
    id: syncProc
    command: ["sh", "-c", "hyprctl clients -j; printf '\\n###MON###\\n'; hyprctl monitors -j"]
    stdout: StdioCollector {
      onStreamFinished: root.applySync(text)
    }
  }

  Timer {
    interval: root.syncInterval
    repeat: true
    triggeredOnStart: true
    running: root.pickerVisible || Object.keys(root.stickers).length > 0 || root.rules.length > 0
    onTriggered: if (!syncProc.running) syncProc.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (ev.name === "closewindow") {
        var raw = Array.isArray(ev.data) ? ev.data[0] : String(ev.data)
        var addr = root.normalizeAddr(raw)
        if (root.stickers[addr]) {
          var next = {}
          for (var k in root.stickers)
            if (k !== addr) next[k] = root.stickers[k]
          root.stickers = next
          root.saveStickers()
        }
      }
      if (!syncProc.running) syncProc.running = true
    }
  }

  function normalizeAddr(a) {
    if (!a) return ""
    return a.indexOf("0x") === 0 ? a : "0x" + a
  }

  function screenByName(name) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return null
  }

  function classOf(c) { return RL.classOf(c) }

  function applySync(raw) {
    var parts = String(raw).split("###MON###")
    var clients, monitors
    try {
      clients = JSON.parse(parts[0])
      monitors = JSON.parse(parts[1])
    } catch (e) {
      return
    }
    root.lastClients = clients

    var monById = {}
    for (var m = 0; m < monitors.length; m++) {
      var mo = monitors[m]
      monById[String(mo.id)] = {
        name: String(mo.name || ""),
        x: mo.x || 0,
        y: mo.y || 0,
        reservedTop: (mo.reserved || [0, 0, 0, 0])[1] || 0,
        activeWs: mo.activeWorkspace ? String(mo.activeWorkspace.name || "") : "",
        specialWs: mo.specialWorkspace ? String(mo.specialWorkspace.name || "") : ""
      }
    }

    // Build the effective sticker set: explicit stickers plus rule matches
    // for windows that don't have an explicit sticker.
    var effective = {}
    for (var addr in root.stickers) effective[addr] = root.stickers[addr]
    for (var ri = 0; ri < clients.length; ri++) {
      var c = clients[ri]
      if (effective[c.address]) continue
      for (var r = 0; r < root.rules.length; r++) {
        if (RL.matches(root.rules[r], c)) {
          effective[c.address] = root.rules[r]
          break
        }
      }
    }

    var S = root.cornerSize
    var seen = {}
    for (var sa in effective) {
      var st = effective[sa]
      var cc2 = null
      for (var ii = 0; ii < clients.length; ii++)
        if (clients[ii].address === sa) { cc2 = clients[ii]; break }
      if (!cc2) continue

      var mon = monById[String(cc2.monitor)]
      var at = cc2.at || [0, 0]
      var size = cc2.size || [0, 0]
      var corner = st.corner || "tr"
      var box = {
        x: corner === "tl" || corner === "bl" ? at[0] : at[0] + size[0] - S,
        y: corner === "tl" || corner === "tr" ? at[1] : at[1] + size[1] - S,
        w: S, h: S
      }
      var occ = Stacking.isVisible(cc2, mon)
        ? Stacking.occlusion(cc2, clients, monById, box, root.borderSize)
        : { full: true, holes: [] }

      var win = root.ribbonWins[sa]
      if (occ.full) {
        if (win) win.visible = false
        continue
      }
      seen[sa] = true
      if (!win) {
        win = ribbonWin.createObject(root)
        root.ribbonWins[sa] = win
      }
      var scr = screenByName(mon.name)
      if (scr && win.screen !== scr) win.screen = scr

      win.targetX = box.x - mon.x
      win.targetY = box.y - mon.y - mon.reservedTop
      win.holes = occ.holes
      win.corner = corner
      win.sstyle = st.style || "banner"
      win.bandColor = root.resolveColor(st.color || "accent")
      win.glow = st.glow === true
      win.ribbonText = st.text || ""
      win.visible = true
    }

    for (var a in root.ribbonWins)
      if (!seen[a]) root.ribbonWins[a].visible = false
  }

  // ---------------------------------------------------------- ribbon window

  Component {
    id: ribbonWin
    PanelWindow {
      id: rib
      property string ribbonText: ""
      property string corner: "tr"
      property string sstyle: "banner"
      property color bandColor: Color.accent
      property bool glow: false
      property real targetX: 0
      property real targetY: 0
      // Parts of the sticker covered by windows stacked above its window.
      property var holes: []

      WlrLayershell.namespace: "omarchy-window-sticker"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.exclusiveZone: 0
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      color: "transparent"
      implicitWidth: root.cornerSize
      implicitHeight: root.cornerSize
      anchors { top: true; left: true }
      margins { left: Math.round(targetX); top: Math.round(targetY) }

      Item {
        id: wrap
        anchors.fill: parent
        transformOrigin: {
          var h = rib.corner === "tl" || rib.corner === "bl" ? Item.Left : Item.Right
          var v = rib.corner === "tl" || rib.corner === "tr" ? Item.Top : Item.Bottom
          if (h === Item.Left && v === Item.Top) return Item.TopLeft
          if (h === Item.Right && v === Item.Top) return Item.TopRight
          if (h === Item.Left && v === Item.Bottom) return Item.BottomLeft
          return Item.BottomRight
        }

        layer.enabled: rib.holes.length > 0
        layer.effect: MultiEffect {
          maskEnabled: true
          maskInverted: true
          maskSource: holeMask
        }

        // optional shadow pass
        StickerArt {
          anchors.fill: parent
          anchors.topMargin: 2; anchors.leftMargin: 2
          visible: rib.glow
          shadow: true
          stickerText: rib.ribbonText
          bandColor: rib.bandColor
          stickerStyle: rib.sstyle
          corner: rib.corner
        }

        StickerArt {
          anchors.fill: parent
          stickerText: rib.ribbonText
          bandColor: rib.bandColor
          stickerStyle: rib.sstyle
          corner: rib.corner
        }

        // Pop-in when the ribbon first appears.
        SequentialAnimation on scale {
          id: popAnim
          running: false
          NumberAnimation { from: 1.35; to: 0.94; duration: 110; easing.type: Easing.OutQuad }
          NumberAnimation { to: 1.0; duration: 90; easing.type: Easing.OutBack }
        }
      }

      Item {
        id: holeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Repeater {
          model: rib.holes
          Rectangle {
            required property var modelData
            x: modelData.x; y: modelData.y
            width: modelData.w; height: modelData.h
            color: "black"
          }
        }
      }

      onVisibleChanged: if (visible) popAnim.restart()
    }
  }

  // ---------------------------------------------------------- picker

  Process {
    id: activeWinProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.openForWindow(text)
    }
  }

  function open(payloadJson) {
    if (activeWinProc.running) return
    activeWinProc.running = true
  }

  function openForWindow(raw) {
    var w
    try { w = JSON.parse(raw) } catch (e) { return }
    if (!w || !w.address) {
      // No focused window: still open in overview mode.
      root.targetAddr = ""
      root.targetClient = null
      root.targetClass = ""
      root.targetLabel = ""
      root.pickerVisible = true
      Qt.callLater(function() { pickerScroll.forceActiveFocus() })
      return
    }
    root.targetAddr = w.address
    root.targetClient = w
    root.targetClass = classOf(w)
    root.targetLabel = root.targetClass
      + (w.title ? " \u2014 " + w.title : "")
    root.targetMonitor = String(w.monitor || "")
    var existing = root.stickers[w.address]
    if (existing) {
      pickerInput.text = existing.text || ""
      root.selectedColor = existing.color || "accent"
      root.selectedCorner = existing.corner || "tr"
      root.selectedStyle = existing.style || "banner"
      root.selectedGlow = existing.glow === true
    } else {
      pickerInput.text = ""
    }
    root.emojiOpen = false
    rulesEditor.cancel()
    root.pickerVisible = true
    Qt.callLater(function() { pickerInput.forceActiveFocus() })
  }

  function close() { root.pickerVisible = false }

  function applySticker() {
    var t = (pickerInput.text || "").trim()
    if (!t || !root.targetAddr) return
    var next = {}
    for (var k in root.stickers) next[k] = root.stickers[k]
    next[root.targetAddr] = {
      text: t,
      color: root.selectedColor,
      corner: root.selectedCorner,
      style: root.selectedStyle,
      glow: root.selectedGlow
    }
    root.stickers = next
    root.saveStickers()
    root.pickerVisible = false
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + root.targetAddr + '" })')
    Qt.callLater(function() { syncProc.running = true })
  }

  function removeStickerFor(addr) {
    if (!addr) return
    var next = {}
    for (var k in root.stickers)
      if (k !== addr) next[k] = root.stickers[k]
    root.stickers = next
    root.saveStickers()
  }

  function removeSticker() {
    removeStickerFor(root.targetAddr)
    root.pickerVisible = false
  }

  function focusWindow(addr) {
    if (!addr) return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
    root.pickerVisible = false
  }

  function applyPreset(p) {
    pickerInput.text = p.text
    root.selectedColor = p.color
    root.selectedCorner = p.corner
    root.selectedStyle = p.style
    Qt.callLater(function() { pickerInput.forceActiveFocus() })
  }

  function insertEmoji(e) {
    pickerInput.text = (pickerInput.text + (pickerInput.text.length ? " " : "") + e)
    pickerInput.cursorPosition = pickerInput.text.length
    pickerInput.forceActiveFocus()
  }

  function replaceRules(next) {
    root.rules = next
    root.saveRules()
  }

  function commitRule(index, rule) {
    var next = root.rules.slice()
    if (index >= 0 && index < next.length) next[index] = rule
    else next.push(rule)
    replaceRules(next)
  }

  function removeRule(index) {
    var next = root.rules.slice()
    next.splice(index, 1)
    replaceRules(next)
  }

  function moveRule(index, delta) {
    var to = index + delta
    if (to < 0 || to >= root.rules.length) return
    var next = root.rules.slice()
    var r = next[index]
    next[index] = next[to]
    next[to] = r
    replaceRules(next)
  }

  function setRuleEnabled(index, enabled) {
    var next = root.rules.slice()
    var r = Object.assign({}, next[index])
    r.enabled = enabled
    next[index] = r
    replaceRules(next)
  }

  function loadRuleLook(rule) {
    pickerInput.text = rule.text || ""
    root.selectedColor = rule.color || "accent"
    root.selectedCorner = rule.corner || "tr"
    root.selectedStyle = rule.style || "banner"
    root.selectedGlow = rule.glow === true
  }

  function clearAll() {
    root.stickers = ({})
    root.saveStickers()
    for (var a in root.ribbonWins)
      root.ribbonWins[a].visible = false
  }

  // Public method so the bar widget can show a count.
  function stickerCount() { return Object.keys(root.stickers).length }

  // ---------------------------------------------------------- picker UI

  // Selectable tile used by the style and corner pickers.
  component Tile: Rectangle {
    id: tile
    property bool selected: false
    signal clicked()
    radius: Style.cornerRadius
    color: selected ? Style.selectedFillFor(Color.menu.text, Color.accent)
      : tileArea.containsMouse ? Style.hoverFillFor(Color.menu.text, Color.accent)
      : Style.normalFillFor(Color.menu.text, Color.accent)
    border.width: 1
    border.color: selected ? Color.accent : Util.alpha(Color.menu.text, Style.normalBorderAlpha * 0.5)
    Behavior on color { ColorAnimation { duration: 120 } }
    MouseArea {
      id: tileArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.clicked()
    }
  }

  component RowLabel: Text {
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  PanelWindow {
    id: picker

    readonly property color fg: Color.menu.text
    readonly property int pad: Style.spacing.panelPadding

    WlrLayershell.namespace: "omarchy-window-sticker-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    color: "transparent"
    visible: root.pickerVisible
    implicitWidth: Style.space(540)
    implicitHeight: Math.min(screen ? screen.height - Style.space(80) : 700,
      pickerCol.implicitHeight + pad * 2)
    screen: screenByName(root.targetMonitor) || Quickshell.screens[0] || null
    anchors { top: true; left: true }
    margins {
      left: screen ? Math.round((screen.width - width) / 2) : 0
      top: screen ? Math.max(0, Math.round((screen.height - height) / 2)) : 0
    }

    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    }

    Flickable {
      id: pickerScroll
      anchors { fill: parent; margins: picker.pad }
      contentHeight: pickerCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Keys.onEscapePressed: root.close()

      Column {
        id: pickerCol
        width: pickerScroll.width
        spacing: Style.spacing.panelGap

        // ---- header
        Column {
          width: parent.width
          spacing: Style.spacing.xxs
          Text {
            text: "Window sticker"
            color: picker.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideMiddle
            text: root.targetLabel || "No focused window \u2014 overview only"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---- live preview: the real window via screencopy, sticker on top
        Rectangle {
          id: previewBox
          visible: root.targetAddr !== ""
          width: parent.width
          height: Style.space(170)
          radius: Style.cornerRadius
          color: Util.alpha(picker.fg, 0.04)
          clip: true

          readonly property var targetToplevel: {
            var tls = Hyprland.toplevels.values
            for (var i = 0; i < tls.length; i++)
              if (root.normalizeAddr(tls[i].address) === root.targetAddr) return tls[i]
            return null
          }
          readonly property real winAspect: {
            var c = root.targetClient
            return c && c.size && c.size[1] > 0 ? c.size[0] / c.size[1] : 16 / 9
          }

          Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.spacing.xxl * 2,
              (parent.height - Style.spacing.xxl * 2) * previewBox.winAspect)
            height: width / previewBox.winAspect
            radius: Style.cornerRadius
            color: Util.alpha(picker.fg, 0.06)
            border.width: 1
            border.color: Util.alpha(picker.fg, 0.15)
            clip: true

            ScreencopyView {
              id: liveCapture
              anchors.fill: parent
              captureSource: previewBox.targetToplevel ? previewBox.targetToplevel.wayland : null
              live: root.pickerVisible
              paintCursor: false
            }

            StickerArt {
              // Real stickers are 110px on a full-size window; keep the same
              // proportion in the scaled-down preview.
              readonly property real ratio: root.targetClient && root.targetClient.size
                ? parent.width / Math.max(1, root.targetClient.size[0]) : 0.25
              width: Math.max(Style.space(40), root.cornerSize * ratio * 2.2)
              height: width
              x: root.selectedCorner === "tl" || root.selectedCorner === "bl" ? 0 : parent.width - width
              y: root.selectedCorner === "tl" || root.selectedCorner === "tr" ? 0 : parent.height - height
              stickerText: pickerInput.text || "Preview"
              bandColor: root.resolveColor(root.selectedColor)
              stickerStyle: root.selectedStyle
              corner: root.selectedCorner
            }
          }
        }

        // ---- label
        Column {
          visible: root.targetAddr !== ""
          width: parent.width
          spacing: Style.spacing.md

          PanelSectionHeader { text: "LABEL" }

          RowLayout {
            width: parent.width
            spacing: Style.spacing.md

            TextField {
              id: pickerInput
              Layout.fillWidth: true
              placeholderText: "e.g. Project X"
              onAccepted: root.applySticker()
              Keys.onEscapePressed: root.emojiOpen ? root.emojiOpen = false : root.close()
            }
            Button {
              bordered: true
              selected: root.emojiOpen
              text: "\uD83D\uDE00"
              tooltipText: "Insert emoji"
              onClicked: root.emojiOpen = !root.emojiOpen
            }
            Button {
              visible: root.stickers[root.targetAddr] !== undefined
              bordered: true
              text: "Remove"
              foreground: Color.urgent
              onClicked: root.removeSticker()
            }
          }

          Flow {
            visible: root.emojiOpen
            width: parent.width
            spacing: Style.spacing.xs
            Repeater {
              model: root.emojiList
              delegate: Button {
                required property var modelData
                text: modelData
                fontSize: Style.font.heading
                onClicked: root.insertEmoji(modelData)
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.spacing.sm
            Repeater {
              model: root.presets
              delegate: Button {
                required property var modelData
                bordered: true
                text: modelData.label
                fontSize: Style.font.caption
                foreground: root.resolveColor(modelData.color)
                selected: pickerInput.text === modelData.text
                  && root.selectedStyle === modelData.style
                  && root.selectedColor === modelData.color
                tooltipText: "\u201c" + modelData.text + "\u201d \u00b7 " + modelData.style
                onClicked: root.applyPreset(modelData)
              }
            }
          }
        }

        // ---- look
        Column {
          visible: root.targetAddr !== ""
          width: parent.width
          spacing: Style.spacing.md

          PanelSectionHeader { text: "LOOK" }

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.spacing.xxl
            rowSpacing: Style.spacing.lg

            RowLabel { text: "Color" }
            Flow {
              Layout.fillWidth: true
              spacing: Style.spacing.md
              Repeater {
                model: root.palette
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool picked: root.selectedColor === modelData
                  width: Style.space(22); height: width; radius: width / 2
                  color: "transparent"
                  border.width: picked ? Math.max(2, Style.space(2)) : 0
                  border.color: picker.fg
                  Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - Style.space(6); height: width; radius: width / 2
                    color: root.resolveColor(parent.modelData)
                    scale: swatchArea.containsMouse && !parent.picked ? 1.15 : 1
                    Behavior on scale { NumberAnimation { duration: 90 } }
                  }
                  MouseArea {
                    id: swatchArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedColor = parent.modelData
                  }
                }
              }
            }

            RowLabel { text: "Style" }
            Flow {
              Layout.fillWidth: true
              spacing: Style.spacing.md
              Repeater {
                model: root.styleModel
                delegate: Tile {
                  required property var modelData
                  width: Style.space(58); height: Style.space(44)
                  selected: root.selectedStyle === modelData.id
                  onClicked: root.selectedStyle = modelData.id
                  StickerArt {
                    anchors { fill: parent; margins: Style.spacing.xs; bottomMargin: Style.space(12) }
                    bandColor: root.resolveColor(root.selectedColor)
                    stickerStyle: parent.modelData.id
                    corner: "tr"
                  }
                  Text {
                    anchors { bottom: parent.bottom; bottomMargin: Style.spacing.xxs; horizontalCenter: parent.horizontalCenter }
                    text: parent.modelData.label
                    color: parent.selected ? picker.fg : Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption - 1
                  }
                }
              }
            }

            RowLabel { text: "Corner" }
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.md
              Repeater {
                model: root.cornerModel
                delegate: Tile {
                  id: cornerTile
                  required property var modelData
                  width: Style.space(46); height: Style.space(34)
                  selected: root.selectedCorner === modelData.id
                  onClicked: root.selectedCorner = modelData.id
                  Rectangle {
                    id: mini
                    anchors.centerIn: parent
                    width: Style.space(30); height: Style.space(20)
                    radius: Math.min(Style.cornerRadius, Style.space(3))
                    color: "transparent"
                    border.width: 1
                    border.color: Util.alpha(picker.fg, 0.4)
                    clip: true
                    Rectangle {
                      width: Style.space(12); height: width; rotation: 45
                      color: root.resolveColor(root.selectedColor)
                      x: cornerTile.modelData.id === "tl" || cornerTile.modelData.id === "bl" ? -width / 2 : mini.width - width / 2
                      y: cornerTile.modelData.id === "tl" || cornerTile.modelData.id === "tr" ? -height / 2 : mini.height - height / 2
                    }
                  }
                }
              }
              Item { Layout.fillWidth: true }
              Text {
                text: "Glow"
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              ToggleSwitch {
                checked: root.selectedGlow
                onToggled: root.selectedGlow = !root.selectedGlow
              }
            }
          }
        }

        Button {
          visible: root.targetAddr !== ""
          anchors.right: parent.right
          bordered: true
          selected: pickerInput.text.trim() !== ""
          enabled: pickerInput.text.trim() !== ""
          opacity: enabled ? 1 : 0.4
          text: root.stickers[root.targetAddr] !== undefined ? "Update sticker  \u21b5" : "Stick it  \u21b5"
          onClicked: root.applySticker()
        }

        PanelSeparator { width: parent.width }

      RulesEditor {
        id: rulesEditor
        width: parent.width
        rules: root.rules
        clients: root.lastClients
        stickers: root.stickers
        target: root.targetClient
        canEdit: root.targetAddr !== ""
        label: pickerInput.text
        stickerColor: root.selectedColor
        stickerStyle: root.selectedStyle
        corner: root.selectedCorner
        glow: root.selectedGlow
        resolveColor: root.resolveColor
        onCommit: function(index, rule) { root.commitRule(index, rule) }
        onRemoveRule: function(index) { root.removeRule(index) }
        onMoveRule: function(index, delta) { root.moveRule(index, delta) }
        onSetRuleEnabled: function(index, enabled) { root.setRuleEnabled(index, enabled) }
        onLoadLook: function(rule) { root.loadRuleLook(rule) }
      onDraftingChanged: if (drafting) Qt.callLater(function() {
        pickerScroll.contentY = Math.max(0, Math.min(rulesEditor.y,
          pickerScroll.contentHeight - pickerScroll.height))
      })
      }

        // ---- stickered windows
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          visible: Object.keys(root.stickers).length > 0

          PanelSectionHeader { text: "STICKERED WINDOWS" }

          Repeater {
            model: {
              var out = []
              var keys = Object.keys(root.stickers)
              for (var i = 0; i < keys.length; i++) {
                var addr = keys[i]
                var c = null
                for (var j = 0; j < root.lastClients.length; j++)
                  if (root.lastClients[j].address === addr) { c = root.lastClients[j]; break }
                out.push({ addr: addr, st: root.stickers[addr], cls: classOf(c), title: c ? String(c.title || "") : "" })
              }
              return out
            }
            delegate: Rectangle {
              id: stRow
              required property var modelData
              width: pickerCol.width
              height: stLayout.implicitHeight + Style.spacing.md * 2
              radius: Style.cornerRadius
              color: stArea.containsMouse ? Style.hoverFillFor(picker.fg, Color.accent) : "transparent"

              MouseArea {
                id: stArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWindow(stRow.modelData.addr)
              }

              RowLayout {
                id: stLayout
                anchors { fill: parent; margins: Style.spacing.md }
                spacing: Style.spacing.lg

                Rectangle {
                  Layout.preferredWidth: Style.space(46)
                  Layout.preferredHeight: Style.space(30)
                  radius: Style.cornerRadius
                  color: Util.alpha(picker.fg, 0.06)
                  clip: true
                  StickerArt {
                    anchors.fill: parent
                    bandColor: root.resolveColor(stRow.modelData.st.color || "accent")
                    stickerStyle: stRow.modelData.st.style || "banner"
                    corner: stRow.modelData.st.corner || "tr"
                  }
                }
                Column {
                  Layout.fillWidth: true
                  spacing: Style.spacing.xxs
                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: stRow.modelData.st.text || ""
                    color: picker.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: (stRow.modelData.cls || "?") + (stRow.modelData.title ? " \u00b7 " + stRow.modelData.title : "")
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
                Button {
                  text: "\u00d7"
                  fontSize: Style.font.subtitle
                  tooltipText: "Remove sticker"
                  onClicked: root.removeStickerFor(stRow.modelData.addr)
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: root.targetAddr !== ""
            ? "Enter sticks it \u00b7 Esc closes \u00b7 click a stickered window to jump to it"
            : "Click a stickered window to jump to it \u00b7 Esc closes"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
