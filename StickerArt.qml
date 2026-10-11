import QtQuick
import QtQuick.Shapes
import qs.Commons

// Reusable sticker drawing. Used by the live ribbon windows, by the picker
// preview, and by overview thumbnails. All geometry scales with the parent's
// size so previews can be arbitrarily small.
Item {
  id: art

  property string stickerText: ""
  property color bandColor: Color.accent
  property string stickerStyle: "banner"
  property string corner: "tr"
  property bool shadow: false

  readonly property real sz: Math.min(width, height)
  readonly property real scale2: sz / 110          // 110 is the reference ribbon size
  readonly property real cut: 48 * scale2
  readonly property real bandT: 22 * scale2

  readonly property real cpx: corner === "tl" || corner === "bl" ? 0 : sz
  readonly property real cpy: corner === "tl" || corner === "tr" ? 0 : sz
  readonly property real inx: corner === "tl" || corner === "bl" ? 1 : -1
  readonly property real iny: corner === "tl" || corner === "tr" ? 1 : -1

  readonly property color fillColor: shadow ? Qt.rgba(0, 0, 0, 0.42) : bandColor
  readonly property color strokeColor: shadow
    ? Qt.rgba(0, 0, 0, 0.25) : Qt.darker(bandColor, 1.28)

  function textFg() {
    if (shadow) return "transparent"
    var s = String(bandColor)
    if (s.charAt(0) === "#" && s.length >= 7) {
      var r = parseInt(s.substr(1, 2), 16)
      var g = parseInt(s.substr(3, 2), 16)
      var b = parseInt(s.substr(5, 2), 16)
      var lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
      return lum > 0.6 ? "#16161e" : "#ffffff"
    }
    return "#ffffff"
  }

  // Text sizing: shrink to keep long labels readable within each style's bounds.
  function autoFontPx(base, textLen, charsAtBase) {
    if (textLen <= charsAtBase) return base
    return Math.max(base - 3, Math.round(base * charsAtBase / textLen))
  }

  clip: true

  // ---- banner: 45-degree diagonal sash ----
  Rectangle {
    visible: art.stickerStyle === "banner"
    width: art.sz * 1.6
    height: art.bandT
    x: art.cpx + art.inx * art.cut / 2 - width / 2
    y: art.cpy + art.iny * art.cut / 2 - height / 2
    rotation: art.corner === "tl" || art.corner === "br" ? -45 : 45
    color: art.fillColor
    antialiasing: true

    Text {
      anchors.fill: parent
      anchors.leftMargin: 12 * art.scale2
      anchors.rightMargin: 12 * art.scale2
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideMiddle
      color: art.textFg()
      font.pixelSize: art.autoFontPx(11 * art.scale2, art.stickerText.length, 10)
      font.bold: true
      text: art.stickerText
    }
  }

  // ---- flag: bookmark tab on the window edge ----
  Shape {
    id: flagShape
    visible: art.stickerStyle === "flag"
    width: 64 * art.scale2
    height: 28 * art.scale2
    readonly property bool flipped: art.corner === "bl" || art.corner === "br"
    x: art.corner === "tl" || art.corner === "bl" ? 0 : art.sz - width
    y: flipped ? art.sz - height : 0
    antialiasing: true

    ShapePath {
      fillColor: art.fillColor
      strokeColor: art.strokeColor
      strokeWidth: 1
      startX: 0; startY: flagShape.flipped ? flagShape.height : 0
      PathLine { x: flagShape.width; y: flagShape.flipped ? flagShape.height : 0 }
      PathLine { x: flagShape.width; y: flagShape.flipped ? 0 : flagShape.height }
      PathLine { x: flagShape.width / 2; y: flagShape.flipped ? 9 * art.scale2 : flagShape.height - 9 * art.scale2 }
      PathLine { x: 0; y: flagShape.flipped ? 0 : flagShape.height }
    }

    Text {
      anchors.fill: parent
      anchors.topMargin: flagShape.flipped ? 9 * art.scale2 : 3 * art.scale2
      anchors.bottomMargin: flagShape.flipped ? 3 * art.scale2 : 9 * art.scale2
      anchors.leftMargin: 6 * art.scale2
      anchors.rightMargin: 6 * art.scale2
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideMiddle
      color: art.textFg()
      font.pixelSize: art.autoFontPx(11 * art.scale2, art.stickerText.length, 9)
      font.bold: true
      text: art.stickerText
    }
  }

  // ---- seal: wax seal badge ----
  Item {
    id: sealHolder
    visible: art.stickerStyle === "seal"
    width: 50 * art.scale2
    height: 50 * art.scale2
    x: art.cpx + art.inx * 32 * art.scale2 - width / 2
    y: art.cpy + art.iny * 32 * art.scale2 - height / 2

    Canvas {
      id: sealCanvas
      anchors.fill: parent
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2, cy = height / 2
        var bumps = 14
        var ringR = width / 2 - 5 * art.scale2
        var bumpR = 4.4 * art.scale2
        ctx.fillStyle = String(art.fillColor)
        for (var i = 0; i < bumps; i++) {
          var a = i * 2 * Math.PI / bumps
          ctx.beginPath()
          ctx.arc(cx + Math.cos(a) * ringR, cy + Math.sin(a) * ringR, bumpR, 0, 2 * Math.PI)
          ctx.fill()
        }
        ctx.beginPath()
        ctx.arc(cx, cy, ringR + 1.5 * art.scale2, 0, 2 * Math.PI)
        ctx.fill()
        if (!art.shadow) {
          ctx.strokeStyle = String(art.strokeColor)
          ctx.lineWidth = Math.max(1, 1.5 * art.scale2)
          ctx.beginPath()
          ctx.arc(cx, cy, ringR - 4.5 * art.scale2, 0, 2 * Math.PI)
          ctx.stroke()
        }
      }
      Connections {
        target: art
        function onFillColorChanged() { sealCanvas.requestPaint() }
        function onStickerTextChanged() { sealCanvas.requestPaint() }
      }
      onVisibleChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    Text {
      anchors.centerIn: sealCanvas
      width: 34 * art.scale2
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideMiddle
      wrapMode: Text.Wrap
      maximumLineCount: 2
      color: art.textFg()
      font.pixelSize: art.autoFontPx(9 * art.scale2, art.stickerText.length, 7)
      font.bold: true
      text: art.stickerText
    }
  }

  // ---- tape: washi strip stuck across the corner ----
  Rectangle {
    id: tapeRect
    visible: art.stickerStyle === "tape"
    width: 84 * art.scale2
    height: 24 * art.scale2
    x: art.cpx + art.inx * 34 * art.scale2 - width / 2
    y: art.cpy + art.iny * 34 * art.scale2 - height / 2
    rotation: (art.corner === "tl" || art.corner === "br" ? 1 : -1) * 7
    opacity: art.shadow ? 0.5 : 0.82
    color: art.fillColor
    border.color: art.strokeColor
    border.width: 1

    Text {
      anchors.fill: parent
      anchors.leftMargin: 8 * art.scale2
      anchors.rightMargin: 8 * art.scale2
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideMiddle
      color: art.textFg()
      font.pixelSize: art.autoFontPx(11 * art.scale2, art.stickerText.length, 10)
      font.bold: true
      text: art.stickerText
    }
  }

  // ---- tag: luggage tag with punched hole ----
  Item {
    id: tagHolder
    visible: art.stickerStyle === "tag"
    width: 78 * art.scale2
    height: 30 * art.scale2
    x: art.cpx + art.inx * 44 * art.scale2 - width / 2
    y: art.cpy + art.iny * 44 * art.scale2 - height / 2
    rotation: (art.corner === "tl" || art.corner === "br" ? 1 : -1) * 8

    Canvas {
      id: tagCanvas
      anchors.fill: parent
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var r = 6 * art.scale2
        var w = width, h = height
        ctx.fillStyle = String(art.fillColor)
        ctx.beginPath()
        ctx.moveTo(r, 0)
        ctx.lineTo(w - r, 0)
        ctx.arcTo(w, 0, w, r, r)
        ctx.lineTo(w, h - r)
        ctx.arcTo(w, h, w - r, h, r)
        ctx.lineTo(r, h)
        ctx.arcTo(0, h, 0, h - r, r)
        ctx.lineTo(0, r)
        ctx.arcTo(0, 0, r, 0, r)
        ctx.closePath()
        ctx.fill()
        ctx.globalCompositeOperation = "destination-out"
        ctx.beginPath()
        ctx.arc(11 * art.scale2, h / 2, 3.5 * art.scale2, 0, 2 * Math.PI)
        ctx.fill()
        ctx.globalCompositeOperation = "source-over"
        if (!art.shadow) {
          ctx.strokeStyle = String(art.strokeColor)
          ctx.lineWidth = 1
          ctx.beginPath()
          ctx.arc(11 * art.scale2, h / 2, 3.5 * art.scale2, 0, 2 * Math.PI)
          ctx.stroke()
        }
      }
      Connections {
        target: art
        function onFillColorChanged() { tagCanvas.requestPaint() }
        function onStickerTextChanged() { tagCanvas.requestPaint() }
      }
      onVisibleChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    Text {
      anchors.fill: parent
      anchors.leftMargin: 19 * art.scale2
      anchors.rightMargin: 8 * art.scale2
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideMiddle
      color: art.textFg()
      font.pixelSize: art.autoFontPx(11 * art.scale2, art.stickerText.length, 9)
      font.bold: true
      text: art.stickerText
    }
  }
}
