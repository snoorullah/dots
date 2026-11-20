pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "parts"

// The logo menu's card (304 wide), driven entirely by `m` from js/Menu.js build(). Nothing here
// runs anything: it reports what was asked and the window (LogoMenu) decides. No task names.
Item {
  id: root

  property var m: ({ head: { t: "", icon: "moon", tone: "accent", r: "" }, secs: [], filtering: false })
  property bool readOnly: false
  property alias filter: input

  signal run(string id)
  signal modePicked(string name)
  signal edited(string q)
  signal keyed(var event)
  signal cancelLogout()
  signal asked()

  width: 304
  height: col.implicitHeight + 2 * Theme.space.m

  function tone(t) { return t === "warn" ? Theme.color.waiting : (t === "accent" ? Theme.color.accent : Theme.color.fgDim) }

  Surface { id: card; objectName: "card"; anchors.fill: parent; corner: Theme.radius.card; fill: 0.97 }

  Column {
    id: col
    x: Theme.space.m; y: Theme.space.m
    width: parent.width - 2 * Theme.space.m
    spacing: 4

    // header
    Item {
      width: parent.width; height: 40
      Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Theme.color.outlineVariant }
      Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.space.m
        anchors.rightMargin: Theme.space.m
        spacing: 10
        Gly { anchors.verticalCenter: parent.verticalCenter; name: root.m.head.icon; box: 20; color: root.tone(root.m.head.tone) }
        DText { objectName: "headTitle"; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 20 - 20 - headRight.implicitWidth; elide: Text.ElideRight; text: root.m.head.t; role: "bodyS"; font.weight: Font.DemiBold; color: root.tone(root.m.head.tone) === Theme.color.fgDim ? Theme.color.fg : root.tone(root.m.head.tone) }
        Cap { id: headRight; objectName: "headRight"; anchors.verticalCenter: parent.verticalCenter; text: root.m.head.r }
      }
    }

    // the filter, when one is typed: it stays in place so the text field keeps its focus
    Rectangle {
      visible: root.m.filtering
      objectName: "filterRow"
      width: parent.width; height: root.m.filtering ? 36 : 0; radius: 8
      color: Theme.color.bg; border.width: 1; border.color: Theme.color.unknown
      Gly { x: Theme.space.m; anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; box: 16; color: Theme.color.fgDim }
      TextInput {
        id: input
        x: 32
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 32 - 40
        readOnly: root.readOnly
        text: root.m.query
        color: Theme.color.fg
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.bodyS
        clip: true
        onTextEdited: root.edited(text)
        Keys.onPressed: event => root.keyed(event)
      }
      Cap { anchors.right: parent.right; anchors.rightMargin: Theme.space.m; anchors.verticalCenter: parent.verticalCenter; text: "Esc" }
    }

    Repeater {
      model: root.m.secs
      Item {
        id: d
        required property var modelData
        readonly property string kind: modelData.kind
        width: col.width
        height: kind === "filter" ? 0
          : kind === "label" ? 20
          : kind === "rule" ? 9
          : kind === "rows" ? rowsCol.implicitHeight
          : kind === "note" ? noteBox.height + 4
          : kind === "empty" ? 72
          : kind === "modes" ? 68
          : kind === "ask" ? 32
          : kind === "countdown" ? 44
          : kind === "session" ? 44
          : kind === "foot" ? 34 : 0

        Cap { visible: d.kind === "label"; x: Theme.space.m; y: 6; text: d.modelData.label; font.letterSpacing: 1; font.capitalization: Font.AllUppercase }

        Rectangle { visible: d.kind === "rule"; y: 4; width: parent.width; height: 1; color: Theme.color.outlineVariant }

        Column {
          id: rowsCol
          visible: d.kind === "rows"
          width: parent.width
          spacing: 0
          Repeater {
            model: d.kind === "rows" ? d.modelData.rows : []
            MenuRow { required property var modelData; objectName: "menuRow"; width: rowsCol.width; r: modelData; onClicked: root.run(modelData.id) }
          }
        }

        Rectangle {
          id: noteBox
          visible: d.kind === "note"
          y: 2
          width: parent.width; height: noteText.implicitHeight + 12; radius: 8
          color: Qt.alpha(root.tone(d.modelData.tone), 0.08)
          border.width: 1; border.color: Theme.color.outlineVariant
          Cap { id: noteText; objectName: "noteText"; x: Theme.space.m; y: 6; width: parent.width - 2 * Theme.space.m; wrapMode: Text.WordWrap; text: d.modelData.text; dim: false; color: Theme.color.fg }
        }

        DText { visible: d.kind === "empty"; objectName: "emptyText"; anchors.centerIn: parent; text: d.modelData.text; role: "bodyS" }

        Grid {
          visible: d.kind === "modes"
          objectName: "modeGrid"
          columns: 3; spacing: 4
          width: parent.width
          Repeater {
            model: d.kind === "modes" ? d.modelData.chips : []
            Rectangle {
              id: chip
              required property var modelData
              objectName: "modeChip"
              property string text: modelData.t
              width: (col.width - 8) / 3; height: 32; radius: 8
              opacity: modelData.locked ? 0.4 : 1
              color: modelData.on ? Theme.color.accent : Theme.color.surfaceContainer
              border.width: 1; border.color: modelData.on ? Theme.color.accent : Theme.color.outlineVariant
              Cap { anchors.centerIn: parent; text: chip.modelData.t; dim: false; color: chip.modelData.on ? Theme.color.accentFg : Theme.color.fg }
              MouseArea { anchors.fill: parent; onClicked: root.modePicked(chip.modelData.t) }
            }
          }
        }

        Rectangle {
          visible: d.kind === "ask"
          objectName: "askRow"
          width: parent.width; height: 32; radius: 8; color: "transparent"
          Row {
            anchors.fill: parent; anchors.leftMargin: Theme.space.m; spacing: 10
            Gly { anchors.verticalCenter: parent.verticalCenter; name: "sparkle"; box: 16; color: Theme.color.accent }
            DText { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16 - 40 - 2 * 10; text: d.modelData.text; role: "bodyS"; color: Theme.color.fgDim }
            Cap { anchors.verticalCenter: parent.verticalCenter; text: d.modelData.sub }
          }
          MouseArea { anchors.fill: parent; onClicked: root.asked() }
        }

        Rectangle {
          visible: d.kind === "countdown"
          objectName: "countdown"
          property string text: root.m.countdownText
          width: parent.width; height: 44; radius: Theme.radius.row; clip: true
          color: Qt.alpha(Theme.color.waiting, 0.1)
          border.width: 1; border.color: Theme.color.waiting
          Row {
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: Theme.space.m; spacing: 10
            Gly { anchors.verticalCenter: parent.verticalCenter; name: "sign-out"; box: 18; color: Theme.color.waiting }
            DText { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 18 - cancel.width - 20; text: root.m.countdownText; role: "bodyS"; font.weight: Font.DemiBold }
            Rectangle {
              id: cancel
              objectName: "cancelBtn"
              anchors.verticalCenter: parent.verticalCenter
              width: cl.implicitWidth + 24; height: 32; radius: 8
              color: Theme.color.accent
              DText { id: cl; anchors.centerIn: parent; text: "Cancel"; role: "bodyS"; font.weight: Font.DemiBold; color: Theme.color.accentFg }
              MouseArea { anchors.fill: parent; onClicked: root.cancelLogout() }
            }
          }
          Rectangle { x: 0; y: parent.height - 3; width: parent.width * (d.modelData.n / 3); height: 3; color: Theme.color.waiting }
        }

        Row {
          visible: d.kind === "session"
          objectName: "sessionRow"
          spacing: 4
          Repeater {
            model: d.kind === "session" ? d.modelData.rows : []
            Rectangle {
              id: sb
              required property var modelData
              objectName: "sessionBtn"
              property string text: modelData.label
              width: (col.width - 4) / 2; height: 44; radius: Theme.radius.row
              color: modelData.selected ? Qt.alpha(Theme.color.accent, Theme.alpha.on) : Theme.color.surfaceContainer
              border.width: 1; border.color: modelData.selected ? Theme.color.accent : Theme.color.outlineVariant
              opacity: sb.modelData.id === "logout" && root.m.logoutDim ? 0.45 : 1
              Row {
                anchors.fill: parent; anchors.leftMargin: 10; spacing: 10
                Gly { anchors.verticalCenter: parent.verticalCenter; name: sb.modelData.icon; box: 18; color: sb.modelData.id === "logout" ? Theme.color.failed : Theme.color.fg }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  DText { text: sb.modelData.label; role: "bodyS" }
                  Cap { visible: sb.modelData.id === "logout" && d.modelData.sub !== ""; text: d.modelData.sub }
                }
              }
              MouseArea { anchors.fill: parent; onClicked: root.run(sb.modelData.id) }
            }
          }
        }

        Item {
          visible: d.kind === "foot"
          width: parent.width; height: 34
          Row {
            x: 0; y: 2; spacing: 10; height: 32
            MenuRow { objectName: "menuRow"; width: 150; r: ({ id: "settings", label: "Settings", icon: "gear", key: "", combo: "", hot: false, selected: false }); onClicked: root.run("settings") }
          }
          Cap { anchors.right: parent.right; anchors.rightMargin: Theme.space.m; anchors.verticalCenter: parent.verticalCenter; text: "local only" }
        }
      }
    }
  }
}
