import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Book-ribbon stickers for Hyprland windows.
//
// Each sticker is a small overlay window pinned to its target window's
// top-right corner; only the ribbon rectangle itself is ever covered. The
// picker panel is summoned with a keybinding: it captures the focused
// window before it takes keyboard focus, you type a label, Enter applies.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property real ribW: 34
  readonly property real ribH: 122
  readonly property real ribNotch: 14
  readonly property real rightInset: 26
  readonly property int syncInterval: 120

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-window-sticker"
  readonly property string stateFile: stateDir + "/stickers.json"

  // address -> { text, class, title }
  property var stickers: ({})
  // address -> PanelWindow (created lazily, reused across moves)
  property var ribbonWins: ({})

  property bool pickerVisible: false
  property string targetAddr: ""
  property string targetLabel: ""
  property string targetMonitor: ""

  readonly property color ribbonFg: Color.accent.hslValue > 0.55 ? "#16161e" : "#ffffff"

  Component.onCompleted: loader.running = true

  // ---------------------------------------------------------- persistence

  Process {
    id: loader
    command: ["cat", root.stateFile]
    stdout: StdioCollector {
      onStreamFinished: {
        var txt = text.trim()
        if (txt) {
          try {
            var obj = JSON.parse(txt)
            if (obj && typeof obj === "object")
              root.stickers = obj
          } catch (e) {
            console.warn("window-sticker: unreadable state file")
          }
        }
        Qt.callLater(function() { syncProc.running = true })
      }
    }
  }

  Process {
    id: saver
  }

  function save() {
    saver.command = ["sh", "-c", "mkdir -p '" + root.stateDir + "' && printf %s '"
      + Qt.btoa(JSON.stringify(root.stickers)) + "' | base64 -d > '" + root.stateFile + "'"]
    saver.running = true
  }

  // ---------------------------------------------------------- tracking
  //
  // hyprctl JSON is the authoritative source: the QML Hyprland toplevel
  // map does not reliably carry focus/geometry state for this use case.

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
    running: Object.keys(root.stickers).length > 0
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
          root.save()
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

  function applySync(raw) {
    var parts = String(raw).split("###MON###")
    var clients, monitors
    try {
      clients = JSON.parse(parts[0])
      monitors = JSON.parse(parts[1])
    } catch (e) {
      return
    }

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

    var seen = {}
    for (var addr in root.stickers) {
      var st = root.stickers[addr]
      var c = null
      for (var i = 0; i < clients.length; i++)
        if (clients[i].address === addr) { c = clients[i]; break }
      if (!c) continue

      var at = c.at || [0, 0]
      var size = c.size || [0, 0]
      var monId = String(c.monitor)
      var monName = ""
      for (var mi = 0; mi < monitors.length; mi++)
        if (String(monitors[mi].id) === monId) { monName = String(monitors[mi].name || ""); break }
      var wsName = c.workspace ? String(c.workspace.name || "") : ""
      var hidden = c.hidden === 1 || c.hidden === true
      var fullscreen = c.fullscreen === 1 || c.fullscreen === true
      var pinned = c.pinned === 1 || c.pinned === true
      var visible = !hidden && !fullscreen
        && (wsName === activeWsByMonId[monId] || wsName === specialWsByMonId[monId] || pinned)

      var win = root.ribbonWins[addr]
      if (!visible) {
        if (win) win.visible = false
        continue
      }
      seen[addr] = true
      if (!win) {
        win = ribbonWin.createObject(root)
        root.ribbonWins[addr] = win
      }
      var scr = screenByName(monName)
      if (scr && win.screen !== scr) win.screen = scr
      win.targetX = at[0] + size[0] - root.ribW - root.rightInset
      win.targetY = at[1] - (reservedTopByMonId[monId] || 0)
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
      property real targetX: 0
      property real targetY: 0

      WlrLayershell.namespace: "omarchy-window-sticker"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.exclusiveZone: 0
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      color: "transparent"
      implicitWidth: root.ribW
      implicitHeight: root.ribH
      anchors { top: true; left: true }
      margins { left: Math.round(targetX); top: Math.round(targetY) }

      Shape {
        anchors.fill: parent
        antialiasing: true
        ShapePath {
          fillColor: Color.accent
          strokeColor: Qt.darker(Color.accent, 1.35)
          strokeWidth: 1
          joinStyle: ShapePath.MiterJoin
          startX: 0; startY: 0
          PathLine { x: root.ribW; y: 0 }
          PathLine { x: root.ribW; y: root.ribH }
          PathLine { x: root.ribW / 2; y: root.ribH - root.ribNotch }
          PathLine { x: 0; y: root.ribH }
        }
      }

      Text {
        width: root.ribH - root.ribNotch - 16
        height: root.ribW
        anchors.centerIn: parent
        rotation: 90
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: root.ribbonFg
        font.pixelSize: 13
        font.bold: true
        text: rib.ribbonText
      }
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
    try {
      w = JSON.parse(raw)
    } catch (e) {
      return
    }
    if (!w || !w.address) return
    root.targetAddr = w.address
    var cls = w.class ? (w.class.initial || w.class.class || "") : ""
    root.targetLabel = cls + (w.title ? " \u2014 " + w.title : "")
    root.targetMonitor = String(w.monitor || "")
    var existing = root.stickers[w.address]
    pickerInput.text = existing ? existing.text : ""
    root.pickerVisible = true
    Qt.callLater(function() { pickerInput.forceActiveFocus() })
  }

  function close() {
    root.pickerVisible = false
  }

  function applySticker(text) {
    text = (text || "").trim()
    if (!text || !root.targetAddr) return
    var next = {}
    for (var k in root.stickers) next[k] = root.stickers[k]
    next[root.targetAddr] = { text: text, label: root.targetLabel }
    root.stickers = next
    root.save()
    root.pickerVisible = false
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + root.targetAddr + '" })')
    Qt.callLater(function() { syncProc.running = true })
  }

  function removeSticker() {
    if (!root.targetAddr) return
    var next = {}
    for (var k in root.stickers)
      if (k !== root.targetAddr) next[k] = root.stickers[k]
    root.stickers = next
    root.save()
    root.pickerVisible = false
  }

  // shell-callable: omarchy-shell shell call io.github.hjanuschka.window-sticker clearAll '{}'
  function clearAll() {
    root.stickers = ({})
    root.save()
    for (var a in root.ribbonWins)
      root.ribbonWins[a].visible = false
  }

  PanelWindow {
    id: picker
    WlrLayershell.namespace: "omarchy-window-sticker-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    focusable: true
    color: "transparent"
    visible: root.pickerVisible
    implicitWidth: 400
    implicitHeight: pickerCol.implicitHeight + 28
    screen: screenByName(root.targetMonitor) || Quickshell.screens[0] || null
    anchors { top: true; left: true }
    margins {
      left: screen ? Math.round((screen.width - width) / 2) : 0
      top: screen ? Math.max(0, Math.round((screen.height - height) / 2 - 80)) : 0
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
      spacing: 8

      Text {
        width: parent.width
        elide: Text.ElideMiddle
        text: root.targetLabel ? "Sticker for: " + root.targetLabel : "No focused window"
        color: Color.menu.text
        opacity: 0.7
        font.pixelSize: 11
      }

      Row {
        width: parent.width
        spacing: 8

        TextInput {
          id: pickerInput
          width: parent.width - (removeBtn.visible ? removeBtn.width + 8 : 0)
          color: Color.menu.text
          font.pixelSize: 15
          clip: true
          onAccepted: root.applySticker(text)
          Keys.onEscapePressed: root.close()
        }

        Rectangle {
          id: removeBtn
          visible: root.targetAddr !== "" && root.stickers[root.targetAddr] !== undefined
          width: visible ? removeLabel.width + 20 : 0
          height: 26
          radius: 8
          color: removeArea.containsMouse
            ? Qt.darker(Color.menu.background, 1.4)
            : Qt.lighter(Color.menu.background, 1.15)
          border.color: Color.menu.border

          Text {
            id: removeLabel
            anchors.centerIn: parent
            text: "Remove"
            color: "#e06c75"
            font.pixelSize: 13
          }

          MouseArea {
            id: removeArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.removeSticker()
          }
        }
      }

      Text {
        text: "Enter to apply \u00b7 Esc to cancel"
        color: Color.menu.text
        opacity: 0.5
        font.pixelSize: 10
      }
    }
  }
}
