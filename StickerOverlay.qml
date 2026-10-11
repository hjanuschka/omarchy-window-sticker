import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

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

  // Composer selection.
  property string selectedColor: "accent"
  property string selectedCorner: "tr"
  property string selectedStyle: "banner"
  property bool selectedGlow: false

  function resolveColor(c) {
    return c === "accent" ? String(Color.accent) : c
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
    running: Object.keys(root.stickers).length > 0 || root.rules.length > 0
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

  function classOf(c) {
    if (!c) return ""
    if (c.class && typeof c.class === "object")
      return String(c.class.initial || c.class.class || "")
    return String(c.class || "")
  }

  function matchRule(rule, c) {
    try {
      if (rule.classRe) {
        if (!new RegExp(rule.classRe, "i").test(classOf(c))) return false
      }
      if (rule.titleRe) {
        if (!new RegExp(rule.titleRe, "i").test(String(c.title || ""))) return false
      }
      return true
    } catch (e) {
      return false
    }
  }

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

    var activeWsByMonId = {}
    var specialWsByMonId = {}
    var reservedTopByMonId = {}
    for (var m = 0; m < monitors.length; m++) {
      activeWsByMonId[String(monitors[m].id)] =
        monitors[m].activeWorkspace ? String(monitors[m].activeWorkspace.name || "") : ""
      specialWsByMonId[String(monitors[m].id)] =
        monitors[m].specialWorkspace ? String(monitors[m].specialWorkspace.name || "") : ""
      var res = monitors[m].reserved || [0, 0, 0, 0]
      reservedTopByMonId[String(monitors[m].id)] = res[1] || 0
    }

    var screensaverActive = false
    var fullscreenByMonId = {}
    for (var ci = 0; ci < clients.length; ci++) {
      var cc = clients[ci]
      if (cc.hidden === 1 || cc.hidden === true) continue
      if (/screensaver|hyprlock|lockscreen|slock/i.test(classOf(cc))) {
        screensaverActive = true
        continue
      }
      if (cc.fullscreen === 1)
        fullscreenByMonId[String(cc.monitor)] = cc.address
    }

    // Build the effective sticker set: explicit stickers plus rule matches
    // for windows that don't have an explicit sticker.
    var effective = {}
    for (var addr in root.stickers) effective[addr] = root.stickers[addr]
    for (var ri = 0; ri < clients.length; ri++) {
      var c = clients[ri]
      if (effective[c.address]) continue
      for (var r = 0; r < root.rules.length; r++) {
        if (matchRule(root.rules[r], c)) {
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

      var at = cc2.at || [0, 0]
      var size = cc2.size || [0, 0]
      var monId = String(cc2.monitor)
      var wsName = cc2.workspace ? String(cc2.workspace.name || "") : ""
      var hidden = cc2.hidden === 1 || cc2.hidden === true
      var pinned = cc2.pinned === 1 || cc2.pinned === true
      var covered = fullscreenByMonId[monId] !== undefined
        && fullscreenByMonId[monId] !== sa
      var visible = !hidden && !screensaverActive && !covered
        && (wsName === activeWsByMonId[monId]
            || wsName === specialWsByMonId[monId]
            || pinned)

      var win = root.ribbonWins[sa]
      if (!visible) {
        if (win) win.visible = false
        continue
      }
      seen[sa] = true
      if (!win) {
        win = ribbonWin.createObject(root)
        root.ribbonWins[sa] = win
      }
      var monName = ""
      for (var mi = 0; mi < monitors.length; mi++)
        if (String(monitors[mi].id) === monId) { monName = String(monitors[mi].name || ""); break }
      var scr = screenByName(monName)
      if (scr && win.screen !== scr) win.screen = scr

      var corner = st.corner || "tr"
      var tx = corner === "tl" || corner === "bl" ? at[0] : at[0] + size[0] - S
      var ty = corner === "tl" || corner === "tr" ? at[1] : at[1] + size[1] - S
      win.targetX = tx
      win.targetY = ty - (reservedTopByMonId[monId] || 0)
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
      root.targetClass = ""
      root.targetLabel = ""
      root.pickerVisible = true
      return
    }
    root.targetAddr = w.address
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

  function addRuleFromCurrent() {
    var t = (pickerInput.text || "").trim()
    if (!t || !root.targetClass) return
    var next = []
    for (var i = 0; i < root.rules.length; i++) next.push(root.rules[i])
    next.push({
      classRe: "^" + root.targetClass + "$",
      titleRe: "",
      text: t,
      color: root.selectedColor,
      corner: root.selectedCorner,
      style: root.selectedStyle,
      glow: root.selectedGlow
    })
    root.rules = next
    root.saveRules()
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

  PanelWindow {
    id: picker
    WlrLayershell.namespace: "omarchy-window-sticker-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    focusable: true
    color: "transparent"
    visible: root.pickerVisible
    implicitWidth: 480
    implicitHeight: Math.min(screen ? screen.height - 80 : 700, pickerCol.implicitHeight + 28)
    screen: screenByName(root.targetMonitor) || Quickshell.screens[0] || null
    anchors { top: true; left: true }
    margins {
      left: screen ? Math.round((screen.width - width) / 2) : 0
      top: screen ? Math.max(0, Math.round((screen.height - height) / 2 - 60)) : 0
    }

    Rectangle {
      anchors.fill: parent
      radius: 14
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 1
    }

    Column {
      id: pickerCol
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
      spacing: 10

      // Target label.
      Text {
        width: parent.width
        elide: Text.ElideMiddle
        text: root.targetLabel ? "Sticker for: " + root.targetLabel : "No focused window (overview only)"
        color: Color.menu.text
        opacity: 0.7
        font.pixelSize: 11
      }

      // Live preview: a fake window with the sticker drawn in the chosen corner.
      Rectangle {
        visible: root.targetAddr !== ""
        width: parent.width
        height: 120
        radius: 10
        color: Qt.darker(Color.menu.background, 1.4)
        border.color: Color.menu.border
        border.width: 1
        clip: true

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - 24, 260)
          height: Math.min(parent.height - 24, 96)
          radius: 6
          color: Qt.lighter(Color.menu.background, 1.08)
          border.color: Qt.tint(Color.menu.text, "#30000000")
          border.width: 1

          // Fake titlebar hints
          Row {
            x: 8; y: 7
            spacing: 5
            Repeater {
              model: 3
              Rectangle { width: 7; height: 7; radius: 3.5; opacity: 0.5
                color: [ "#e5484d", "#ffb224", "#30a46c" ][index] }
            }
          }

          StickerArt {
            anchors.fill: parent
            stickerText: pickerInput.text || "Preview"
            bandColor: root.resolveColor(root.selectedColor)
            stickerStyle: root.selectedStyle
            corner: root.selectedCorner
          }
        }
      }

      // Preset chips.
      Flow {
        visible: root.targetAddr !== ""
        width: parent.width
        spacing: 6
        Repeater {
          model: root.presets
          delegate: Rectangle {
            required property var modelData
            height: 24
            width: presetLabel.width + 18
            radius: 12
            color: presetArea.containsMouse
              ? Qt.lighter(Color.menu.background, 1.2)
              : Qt.darker(Color.menu.background, 1.1)
            border.color: Color.menu.border

            Rectangle {
              anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
              width: 8; height: 8; radius: 4
              color: root.resolveColor(modelData.color)
            }
            Text {
              id: presetLabel
              anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 18 }
              text: modelData.label
              color: Color.menu.text
              font.pixelSize: 10
              font.bold: true
            }
            MouseArea {
              id: presetArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.applyPreset(modelData)
            }
          }
        }
      }

      // Label row: text input + emoji toggle + remove button.
      Row {
        visible: root.targetAddr !== ""
        width: parent.width
        spacing: 8

        Rectangle {
          width: parent.width - emojiBtn.width - 8 - (removeBtn.visible ? removeBtn.width + 8 : 0)
          height: 32
          radius: 8
          color: Qt.darker(Color.menu.background, 1.25)
          border.color: pickerInput.activeFocus ? Color.accent : Color.menu.border
          border.width: 1

          TextInput {
            id: pickerInput
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            color: Color.menu.text
            font.pixelSize: 14
            clip: true
            onAccepted: root.applySticker()
            Keys.onEscapePressed: root.emojiOpen ? root.emojiOpen = false : root.close()
          }
        }

        Rectangle {
          id: emojiBtn
          width: 32; height: 32; radius: 8
          color: root.emojiOpen
            ? Qt.lighter(Color.menu.background, 1.3)
            : (emojiArea.containsMouse ? Qt.lighter(Color.menu.background, 1.15) : "transparent")
          border.color: Color.menu.border
          Text { anchors.centerIn: parent; text: "\uD83D\uDE00"; font.pixelSize: 16 }
          MouseArea {
            id: emojiArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.emojiOpen = !root.emojiOpen
          }
        }

        Rectangle {
          id: removeBtn
          visible: root.targetAddr !== "" && root.stickers[root.targetAddr] !== undefined
          width: visible ? removeLabel.width + 20 : 0
          height: 32
          radius: 8
          color: removeArea.containsMouse
            ? Qt.darker(Color.menu.background, 1.4)
            : Qt.lighter(Color.menu.background, 1.15)
          border.color: Color.menu.border
          Text { id: removeLabel; anchors.centerIn: parent; text: "Remove"; color: "#e06c75"; font.pixelSize: 13 }
          MouseArea {
            id: removeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeSticker()
          }
        }
      }

      // Emoji palette (collapsed by default).
      Flow {
        visible: root.pickerVisible && root.emojiOpen && root.targetAddr !== ""
        width: parent.width
        spacing: 4
        Repeater {
          model: root.emojiList
          delegate: Rectangle {
            required property var modelData
            width: 30; height: 30; radius: 6
            color: emArea.containsMouse ? Qt.lighter(Color.menu.background, 1.2) : "transparent"
            Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 16 }
            MouseArea {
              id: emArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.insertEmoji(modelData)
            }
          }
        }
      }

      // Color row.
      Row {
        visible: root.targetAddr !== ""
        spacing: 8
        Text {
          text: "COLOR"
          color: Color.menu.text; opacity: 0.45
          font.pixelSize: 9; font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Repeater {
          model: root.palette
          delegate: Rectangle {
            required property var modelData
            width: 22; height: 22; radius: 11
            anchors.verticalCenter: parent.verticalCenter
            color: root.resolveColor(modelData)
            border.width: root.selectedColor === modelData ? 2 : 1
            border.color: root.selectedColor === modelData
              ? Color.menu.text : Qt.darker(root.resolveColor(modelData), 1.25)
            scale: swatchArea.containsMouse ? 1.18 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            MouseArea {
              id: swatchArea
              anchors.fill: parent; hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedColor = modelData
            }
          }
        }
      }

      // Style row.
      Row {
        visible: root.targetAddr !== ""
        spacing: 8
        Text {
          text: "STYLE"
          color: Color.menu.text; opacity: 0.45
          font.pixelSize: 9; font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Repeater {
          model: root.styleModel
          delegate: Rectangle {
            required property var modelData
            width: 52; height: 36; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: styleArea.containsMouse ? Qt.lighter(Color.menu.background, 1.15) : "transparent"
            border.width: root.selectedStyle === modelData.id ? 2 : 1
            border.color: root.selectedStyle === modelData.id ? Color.accent : Color.menu.border

            StickerArt {
              anchors { fill: parent; margins: 4 }
              stickerText: ""
              bandColor: root.resolveColor(root.selectedColor)
              stickerStyle: modelData.id
              corner: "tr"
            }
            MouseArea {
              id: styleArea
              anchors.fill: parent; hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedStyle = modelData.id
            }
          }
        }
      }

      // Corner row + glow toggle.
      Row {
        visible: root.targetAddr !== ""
        spacing: 8
        Text {
          text: "CORNER"
          color: Color.menu.text; opacity: 0.45
          font.pixelSize: 9; font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Repeater {
          model: root.cornerModel
          delegate: Rectangle {
            required property var modelData
            width: 46; height: 34; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: cornerArea.containsMouse ? Qt.lighter(Color.menu.background, 1.15) : "transparent"
            border.width: root.selectedCorner === modelData.id ? 2 : 1
            border.color: root.selectedCorner === modelData.id ? Color.accent : Color.menu.border

            Rectangle {
              id: mini
              anchors.centerIn: parent
              width: 32; height: 22; radius: 2
              color: "transparent"
              border.color: Qt.tint(Color.menu.text, "#40000000")
              border.width: 1
              clip: true
              Rectangle {
                width: 13; height: 13; rotation: 45
                color: root.resolveColor(root.selectedColor)
                x: modelData.id === "tl" || modelData.id === "bl" ? -6.5 : mini.width - 6.5
                y: modelData.id === "tl" || modelData.id === "tr" ? -6.5 : mini.height - 6.5
              }
            }
            MouseArea {
              id: cornerArea
              anchors.fill: parent; hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedCorner = modelData.id
            }
          }
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 60; height: 24; radius: 12
          color: root.selectedGlow
            ? Qt.lighter(Color.menu.background, 1.3)
            : Qt.darker(Color.menu.background, 1.1)
          border.color: root.selectedGlow ? Color.accent : Color.menu.border
          Text {
            anchors.centerIn: parent
            text: "glow"
            color: Color.menu.text
            opacity: root.selectedGlow ? 1 : 0.6
            font.pixelSize: 10
            font.bold: true
          }
          MouseArea {
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectedGlow = !root.selectedGlow
          }
        }
      }

      // Rule button.
      Row {
        visible: root.targetAddr !== ""
        spacing: 8
        Rectangle {
          width: ruleLabel.width + 20; height: 24; radius: 12
          color: ruleArea.containsMouse
            ? Qt.lighter(Color.menu.background, 1.2)
            : Qt.darker(Color.menu.background, 1.1)
          border.color: Color.menu.border
          Text {
            id: ruleLabel
            anchors.centerIn: parent
            text: "+ Save as rule for " + (root.targetClass || "class")
            color: Color.menu.text
            opacity: 0.75
            font.pixelSize: 10
          }
          MouseArea {
            id: ruleArea
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.addRuleFromCurrent()
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.rules.length > 0 ? root.rules.length + " rule(s) active" : ""
          color: Color.menu.text; opacity: 0.4
          font.pixelSize: 9
        }
      }

      // Overview: existing stickers.
      Column {
        width: parent.width
        spacing: 4
        visible: Object.keys(root.stickers).length > 0

        Text {
          text: "STICKERED WINDOWS"
          color: Color.menu.text; opacity: 0.45
          font.pixelSize: 9; font.bold: true
        }

        Repeater {
          model: {
            var out = []
            var keys = Object.keys(root.stickers)
            for (var i = 0; i < keys.length; i++) {
              var addr = keys[i]
              var st = root.stickers[addr]
              var cls = ""
              var title = ""
              for (var j = 0; j < root.lastClients.length; j++) {
                if (root.lastClients[j].address === addr) {
                  cls = classOf(root.lastClients[j])
                  title = String(root.lastClients[j].title || "")
                  break
                }
              }
              out.push({ addr: addr, st: st, cls: cls, title: title })
            }
            return out
          }
          delegate: Rectangle {
            required property var modelData
            width: pickerCol.width
            height: 36; radius: 6
            color: rowArea.containsMouse
              ? Qt.lighter(Color.menu.background, 1.1) : "transparent"

            Rectangle {
              id: thumb
              anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 4 }
              width: 48; height: 30; radius: 3
              color: Qt.darker(Color.menu.background, 1.3)
              clip: true
              StickerArt {
                anchors.fill: parent
                stickerText: ""
                bandColor: root.resolveColor(modelData.st.color || "accent")
                stickerStyle: modelData.st.style || "banner"
                corner: modelData.st.corner || "tr"
              }
            }

            Column {
              anchors { left: thumb.right; right: rmBtn.left; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
              spacing: 1
              Text {
                width: parent.width
                text: (modelData.cls || "?") + "  \u2014  \"" + (modelData.st.text || "") + "\""
                color: Color.menu.text
                font.pixelSize: 11
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: modelData.title
                color: Color.menu.text; opacity: 0.5
                font.pixelSize: 9
                elide: Text.ElideRight
              }
            }

            Rectangle {
              id: rmBtn
              anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 4 }
              width: 22; height: 22; radius: 11
              color: rmArea.containsMouse ? "#e06c75" : "transparent"
              Text { anchors.centerIn: parent; text: "\u00d7"; color: Color.menu.text; font.pixelSize: 14 }
              MouseArea {
                id: rmArea
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.removeStickerFor(modelData.addr)
              }
            }

            MouseArea {
              id: rowArea
              anchors { left: parent.left; right: rmBtn.left; top: parent.top; bottom: parent.bottom }
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.focusWindow(modelData.addr)
            }
          }
        }
      }

      Text {
        text: root.targetAddr !== ""
          ? "Enter apply \u00b7 Esc cancel \u00b7 click a row to focus that window"
          : "Click a row to focus that window \u00b7 Esc to close"
        color: Color.menu.text; opacity: 0.4
        font.pixelSize: 10
      }
    }
  }
}
