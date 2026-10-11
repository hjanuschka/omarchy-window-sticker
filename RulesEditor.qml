import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "RuleLogic.js" as RL

// Rule list + editor. The sticker look (label, color, style, corner, glow)
// always comes from the picker's composer; this component owns only the
// match conditions and shows, live, which open windows a draft would hit.
Column {
  id: ed

  property var rules: []
  property var clients: []
  property var stickers: ({})
  property var target: null
  property bool canEdit: true

  // Composer state, read-only here.
  property string label: ""
  property string stickerColor: "accent"
  property string stickerStyle: "banner"
  property string corner: "tr"
  property bool glow: false
  property var resolveColor: function(c) { return c }

  property int editingIndex: -1
  property bool drafting: false
  property string classMode: "exact"
  property string classText: ""
  property string titleMode: "contains"
  property string titleText: ""

  signal commit(int index, var rule)
  signal removeRule(int index)
  signal moveRule(int index, int delta)
  signal setRuleEnabled(int index, bool enabled)
  signal loadLook(var rule)

  readonly property string classRe: RL.compile(classMode, classText)
  readonly property string titleRe: RL.compile(titleMode, titleText)
  readonly property string classError: classMode === "regex" ? RL.validate(classRe) : ""
  readonly property string titleError: titleMode === "regex" ? RL.validate(titleRe) : ""
  readonly property bool hasCondition: classRe !== "" || titleRe !== ""
  readonly property var analysis: drafting && hasCondition && !classError && !titleError
    ? RL.analyze({ classRe: classRe, titleRe: titleRe },
        editingIndex >= 0 ? editingIndex : rules.length, rules, clients, stickers)
    : RL.analyze(null)
  readonly property var suggestionList: RL.suggestions(target)
  readonly property bool broad: analysis.total >= 4 && analysis.matched > analysis.total / 2
  readonly property string blocker: {
    if (!label.trim()) return "Type a label in the composer above"
    if (!hasCondition) return "Add at least one condition"
    if (classError || titleError) return "Fix the pattern first"
    return ""
  }

  readonly property color fg: Color.menu.text
  readonly property color muted: Color.muted
  readonly property var modeOptions: [
    { value: "exact", label: "is" },
    { value: "contains", label: "has" },
    { value: "starts", label: "starts" },
    { value: "regex", label: "regex" }
  ]

  spacing: Style.spacing.md

  function startNew() {
    editingIndex = -1
    classMode = "exact"
    classText = target ? RL.classOf(target) : ""
    titleMode = "contains"
    titleText = ""
    drafting = true
  }

  function startEdit(i) {
    var r = rules[i]
    if (!r) return
    var cf = RL.fieldOf(r, "class")
    var tf = RL.fieldOf(r, "title")
    classMode = cf.mode; classText = cf.text
    titleMode = tf.mode; titleText = tf.text
    editingIndex = i
    drafting = true
    loadLook(r)
  }

  function cancel() {
    drafting = false
    editingIndex = -1
  }

  function applySuggestion(s) {
    if (s.field === "class") { classMode = s.mode; classText = s.text }
    else { titleMode = s.mode; titleText = s.text }
  }

  function suggestionActive(s) {
    return s.field === "class"
      ? classMode === s.mode && classText === s.text
      : titleMode === s.mode && titleText === s.text
  }

  function save() {
    if (blocker) return
    var prev = editingIndex >= 0 ? rules[editingIndex] : null
    commit(editingIndex, {
      classMode: classMode, classText: classText.trim(), classRe: classRe,
      titleMode: titleMode, titleText: titleText.trim(), titleRe: titleRe,
      text: label.trim(), color: stickerColor, style: stickerStyle,
      corner: corner, glow: glow,
      enabled: prev ? prev.enabled !== false : true
    })
    cancel()
  }

  function statusLine(stats) {
    if (stats.applies > 0)
      return { text: "on " + stats.applies + " open window" + (stats.applies === 1 ? "" : "s"), color: Color.accent }
    if (stats.matched === 0)
      return { text: "no open window matches", color: ed.muted }
    if (stats.shadowed > 0) {
      for (var i = 0; i < stats.windows.length; i++)
        if (stats.windows[i].by >= 0)
          return { text: "never applies \u2014 rule " + (stats.windows[i].by + 1) + " wins", color: Color.urgent }
    }
    return { text: "matching windows have their own sticker", color: ed.muted }
  }

  // ---------------------------------------------------------- header

  Item {
    width: ed.width
    height: Math.max(headerText.implicitHeight, newBtn.implicitHeight)

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.md
      PanelSectionHeader { id: headerText; text: "RULES" }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ed.rules.length ? String(ed.rules.length) : ""
        color: ed.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Button {
      id: newBtn
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      visible: ed.canEdit && !ed.drafting
      bordered: true
      text: "+ New rule"
      fontSize: Style.font.caption
      onClicked: ed.startNew()
    }
  }

  Text {
    width: ed.width
    wrapMode: Text.Wrap
    text: !ed.canEdit
      ? "Focus a window and press Super+Shift+R to edit rules."
      : ed.rules.length === 0 && !ed.drafting
        ? "Rules sticker windows automatically when they open \u2014 e.g. every kitty whose title has \u201cprod\u201d."
        : "First match wins \u00b7 a window's own sticker beats any rule."
    color: ed.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  // ---------------------------------------------------------- rule list

  Repeater {
    model: ed.rules
    delegate: Rectangle {
      id: row
      required property var modelData
      required property int index
      readonly property var stats: RL.analyze(modelData, index, ed.rules, ed.clients, ed.stickers)
      readonly property var status: ed.statusLine(stats)
      readonly property bool editing: ed.editingIndex === index

      width: ed.width
      height: rowLayout.implicitHeight + Style.spacing.md * 2
      radius: Style.cornerRadius
      color: editing ? Style.selectedFillFor(ed.fg, Color.accent)
        : rowArea.containsMouse ? Style.hoverFillFor(ed.fg, Color.accent)
        : "transparent"
      border.width: editing ? 1 : 0
      border.color: Color.accent

      MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: ed.canEdit
        cursorShape: Qt.PointingHandCursor
        onClicked: ed.editingIndex === row.index ? ed.cancel() : ed.startEdit(row.index)
      }

      RowLayout {
        id: rowLayout
        anchors { fill: parent; margins: Style.spacing.md }
        spacing: Style.spacing.lg

        Column {
          visible: ed.canEdit && ed.rules.length > 1
          spacing: 0
          Button {
            text: "\u25b4"
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.xs
            verticalPadding: 0
            enabled: row.index > 0
            opacity: enabled ? 1 : 0.25
            tooltipText: "Higher priority"
            onClicked: ed.moveRule(row.index, -1)
          }
          Button {
            text: "\u25be"
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.xs
            verticalPadding: 0
            enabled: row.index < ed.rules.length - 1
            opacity: enabled ? 1 : 0.25
            tooltipText: "Lower priority"
            onClicked: ed.moveRule(row.index, 1)
          }
        }

        Rectangle {
          Layout.preferredWidth: Style.space(46)
          Layout.preferredHeight: Style.space(30)
          radius: Style.cornerRadius
          color: Util.alpha(ed.fg, 0.06)
          clip: true
          opacity: row.modelData.enabled === false ? 0.4 : 1
          StickerArt {
            anchors.fill: parent
            bandColor: ed.resolveColor(row.modelData.color || "accent")
            stickerStyle: row.modelData.style || "banner"
            corner: row.modelData.corner || "tr"
          }
        }

        Column {
          Layout.fillWidth: true
          spacing: Style.spacing.xxs
          opacity: row.modelData.enabled === false ? 0.5 : 1

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: (row.index + 1) + ".  " + (row.modelData.text || "")
            color: ed.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: RL.describe(row.modelData)
            color: ed.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: row.modelData.enabled === false ? "paused" : row.status.text
            color: row.modelData.enabled === false ? ed.muted : row.status.color
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        ToggleSwitch {
          visible: ed.canEdit
          checked: row.modelData.enabled !== false
          onToggled: ed.setRuleEnabled(row.index, !checked)
        }

        Button {
          visible: ed.canEdit
          text: "\u00d7"
          fontSize: Style.font.subtitle
          tooltipText: "Delete rule"
          onClicked: {
            if (ed.editingIndex === row.index) ed.cancel()
            ed.removeRule(row.index)
          }
        }
      }
    }
  }

  // ---------------------------------------------------------- editor

  Rectangle {
    visible: ed.drafting
    width: ed.width
    height: form.implicitHeight + Style.spacing.xxl * 2
    radius: Style.cornerRadius
    color: Style.normalFillFor(ed.fg, Color.accent)
    border.width: 1
    border.color: Util.alpha(Color.accent, 0.5)

    Column {
      id: form
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.spacing.xxl }
      spacing: Style.spacing.lg

      // Title + the look this rule will apply.
      RowLayout {
        width: form.width
        spacing: Style.spacing.lg

        Column {
          Layout.fillWidth: true
          spacing: Style.spacing.xxs
          Text {
            text: ed.editingIndex >= 0 ? "Edit rule " + (ed.editingIndex + 1) : "New rule"
            color: ed.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: ed.label.trim()
              ? "Sticks \u201c" + ed.label.trim() + "\u201d \u00b7 look comes from the composer above"
              : "Set the label and look in the composer above"
            color: ed.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          Layout.preferredWidth: Style.space(56)
          Layout.preferredHeight: Style.space(36)
          radius: Style.cornerRadius
          color: Util.alpha(ed.fg, 0.06)
          clip: true
          StickerArt {
            anchors.fill: parent
            bandColor: ed.resolveColor(ed.stickerColor)
            stickerStyle: ed.stickerStyle
            corner: ed.corner
          }
        }
      }

      // Conditions.
      Repeater {
        model: [
          { field: "class", title: "App", placeholder: "any app" },
          { field: "title", title: "Window title", placeholder: "any title" }
        ]
        delegate: Column {
          id: cond
          required property var modelData
          readonly property string err: modelData.field === "class" ? ed.classError : ed.titleError
          width: form.width
          spacing: Style.spacing.sm

          Item {
            width: parent.width
            height: modeGroup.implicitHeight
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: cond.modelData.title
              color: ed.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            ButtonGroup {
              id: modeGroup
              anchors.right: parent.right
              options: ed.modeOptions
              value: ed[cond.modelData.field + "Mode"]
              fontSize: Style.font.caption
              spacing: Style.spacing.xs
              onChanged: function(v) { ed[cond.modelData.field + "Mode"] = v }
            }
          }

          TextField {
            width: parent.width
            text: ed[cond.modelData.field + "Text"]
            placeholderText: cond.modelData.placeholder
            font.pixelSize: Style.font.bodySmall
            foreground: cond.err ? Color.urgent : ed.fg
            onTextEdited: ed[cond.modelData.field + "Text"] = text
            onAccepted: ed.save()
            Keys.onEscapePressed: ed.cancel()
          }

          Text {
            visible: cond.err !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: cond.err
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Suggestions from the focused window.
      Column {
        visible: ed.suggestionList.length > 0
        width: form.width
        spacing: Style.spacing.sm

        Text {
          text: "Suggested from " + RL.classOf(ed.target)
          color: ed.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Flow {
          width: parent.width
          spacing: Style.spacing.sm
          Repeater {
            model: ed.suggestionList
            delegate: Button {
              required property var modelData
              bordered: true
              selected: ed.suggestionActive(modelData)
              text: modelData.label
              fontSize: Style.font.caption
              verticalPadding: Style.spacing.xs
              tooltipText: (modelData.field === "class" ? "App " : "Title ") + modelData.mode + ": " + modelData.text
              onClicked: ed.applySuggestion(modelData)
            }
          }
        }
      }

      PanelSeparator { width: form.width }

      // Live match analysis.
      Column {
        width: form.width
        spacing: Style.spacing.sm

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: !ed.hasCondition ? "Add a condition to see which windows match."
            : ed.classError || ed.titleError ? "Pattern has an error."
            : ed.analysis.matched === 0 ? "No open window matches \u2014 it will apply once one opens."
            : ed.analysis.applies + " of " + ed.analysis.total + " open windows get this sticker"
          color: ed.analysis.applies > 0 ? ed.fg : ed.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: ed.analysis.applies > 0
        }

        Text {
          visible: text !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: {
            var parts = []
            if (ed.analysis.explicit > 0) parts.push(ed.analysis.explicit + " keep their own sticker")
            if (ed.analysis.shadowed > 0) parts.push(ed.analysis.shadowed + " already taken by an earlier rule")
            return parts.join(" \u00b7 ")
          }
          color: ed.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: ed.broad
          width: parent.width
          wrapMode: Text.Wrap
          text: "Very broad: matches " + ed.analysis.matched + " of " + ed.analysis.total
            + " windows. Add a title condition to narrow it down."
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.sm
          Repeater {
            model: ed.analysis.windows.slice(0, 8)
            delegate: Rectangle {
              required property var modelData
              readonly property color dot: modelData.status === "applies" ? Color.accent
                : modelData.status === "shadowed" ? Color.urgent : ed.muted
              height: pillText.implicitHeight + Style.spacing.xs * 2
              width: Math.min(pillText.implicitWidth, Style.space(200)) + Style.spacing.lg * 2 + Style.space(8)
              radius: height / 2
              color: Util.alpha(dot, 0.12)
              border.width: ed.target && modelData.address === ed.target.address ? 1 : 0
              border.color: dot

              Rectangle {
                anchors { left: parent.left; leftMargin: Style.spacing.md; verticalCenter: parent.verticalCenter }
                width: Style.space(6); height: width; radius: width / 2
                color: parent.dot
              }
              Text {
                id: pillText
                anchors { left: parent.left; leftMargin: Style.spacing.md + Style.space(10); verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, Style.space(200))
                elide: Text.ElideRight
                text: (modelData.status === "shadowed" ? "rule " + (modelData.by + 1) + " \u00b7 "
                    : modelData.status === "explicit" ? "own \u00b7 " : "")
                  + modelData.cls + (modelData.title ? " \u00b7 " + modelData.title : "")
                color: ed.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
          Text {
            visible: ed.analysis.windows.length > 8
            text: "+" + (ed.analysis.windows.length - 8) + " more"
            color: ed.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Actions.
      RowLayout {
        width: form.width
        spacing: Style.spacing.md

        Text {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: ed.blocker
          color: ed.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Button {
          text: "Cancel"
          fontSize: Style.font.caption
          onClicked: ed.cancel()
        }
        Button {
          bordered: true
          selected: ed.blocker === ""
          enabled: ed.blocker === ""
          opacity: enabled ? 1 : 0.4
          text: ed.editingIndex >= 0 ? "Update rule" : "Save rule"
          fontSize: Style.font.caption
          onClicked: ed.save()
        }
      }
    }
  }
}
