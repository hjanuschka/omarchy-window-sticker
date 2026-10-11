import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Tiny bar entry: shows a label icon and the number of currently-stickered
// windows. Clicking it opens the sticker picker in overview mode so you can
// jump to any stickered window.
BarWidget {
  id: root
  moduleName: "io.github.hjanuschka.window-sticker"

  readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state"))
    + "/omarchy-window-sticker/stickers.json"

  property int stickerCount: 0

  FileView {
    path: root.stateFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var obj = JSON.parse(String(text() || "{}"))
        root.stickerCount = obj && typeof obj === "object"
          ? Object.keys(obj).length : 0
      } catch (e) { root.stickerCount = 0 }
    }
    onLoadFailed: root.stickerCount = 0
  }

  Process {
    id: opener
    command: ["omarchy-shell", "shell", "summon",
      "io.github.hjanuschka.window-sticker", "{}"]
  }

  implicitWidth: pill.implicitWidth
  implicitHeight: Math.max(18, barSize - 10)

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: row.implicitWidth + 14
    height: parent.height
    radius: height / 2
    color: hover.containsMouse
      ? Qt.lighter(root.bar ? root.bar.background : Color.menu.background, 1.2)
      : "transparent"
    border.color: root.bar ? root.bar.foreground : Color.menu.border
    border.width: 1
    opacity: hover.containsMouse ? 1 : 0.8
    Behavior on opacity { NumberAnimation { duration: 100 } }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: 4
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uD83C\uDFF7\uFE0F"
        font.pixelSize: 11
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.stickerCount
        color: root.bar ? root.bar.foreground : Color.menu.text
        font.pixelSize: 11
        font.bold: true
      }
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: opener.running = true
    }
  }
}
