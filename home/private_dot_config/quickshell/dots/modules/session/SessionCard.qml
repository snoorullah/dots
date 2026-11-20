pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../common"
import "js/Session.js" as S

// The session card: lock, log out, suspend, reboot, shut down, back up then shut down.
// `buttons` comes from Session.sessionButtons. When `blocker` says a long command runs, the
// destructive buttons are grey and the note underneath names the command and the pane.
Item {
  id: root

  property var buttons: []
  property var blocker: ({ blocked: false })
  readonly property bool blocked: !!(blocker && blocker.blocked)
  signal activated(var act)
  signal closed()

  implicitHeight: col.implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.xl - 2

    Item {
      width: parent.width
      height: 28
      DText { role: "caption"; text: "Session"; anchors.verticalCenter: parent.verticalCenter }
      Item {
        width: 28; height: 28
        anchors.right: parent.right
        SessGlyph { anchors.centerIn: parent; key: "close"; boardSize: 16; color: Theme.color.fgDim }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closed() }
      }
    }

    GridLayout {
      width: parent.width
      columns: 2
      columnSpacing: 6
      rowSpacing: 6
      uniformCellWidths: true
      Repeater {
        model: root.buttons
        Item {
          id: sb
          required property var modelData
          objectName: "sess-" + modelData.id
          readonly property bool live: !S.disabled(modelData.act)
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(58, texts.implicitHeight + 16)
          opacity: live ? 1 : 0.45
          Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.alpha(Theme.color.fg, sbArea.containsMouse && sb.live ? Theme.alpha.hover : Theme.alpha.rest * 1.5)
            border.width: 1
            border.color: Qt.alpha(Theme.color.fg, Theme.alpha.divider / 2)
          }
          Row {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 10
            SessGlyph {
              anchors.verticalCenter: parent.verticalCenter
              key: sb.modelData.id
              boardSize: 20
              color: sb.modelData.danger ? Theme.color.failed : Theme.color.fg
            }
            Column {
              id: texts
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 20 - 10
              DText {
                width: parent.width
                role: "bodyS"
                font.weight: 700
                wrapMode: Text.WordWrap
                text: sb.modelData.title
                color: sb.modelData.danger ? Theme.color.failed : Theme.color.fg
              }
              DText {
                width: parent.width
                role: "caption"
                font.capitalization: Font.MixedCase
                font.letterSpacing: 0
                font.weight: Theme.font.weight.body
                dim: true
                wrapMode: Text.WordWrap
                // a grey button that is not just blocked says why it is grey
                text: !sb.live && !root.blocked ? sb.modelData.act.why : sb.modelData.sub
              }
            }
          }
          MouseArea {
            id: sbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: sb.live ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (sb.live) root.activated(sb.modelData.act)
          }
        }
      }
    }

    DText {
      objectName: "uncheckedNote"
      visible: !!(root.blocker && root.blocker.unchecked)
      width: parent.width
      role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true
      wrapMode: Text.WordWrap
      text: "Could not check running commands. Make sure nothing is mid-run."
    }

    Flow {
      id: note
      objectName: "blockNote"
      visible: root.blocked
      width: parent.width
      spacing: 4
      DText { role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true; text: "Blocked while" }
      Rectangle {
        height: Theme.font.line.caption
        width: cmd.implicitWidth + 8
        radius: Theme.radius.chip
        color: Qt.alpha(Theme.color.fg, Theme.alpha.rest * 2)
        DText { id: cmd; anchors.centerIn: parent; mono: true; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0
                text: root.blocker && root.blocker.cmd ? root.blocker.cmd : "" }
      }
      DText { role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true
              text: "runs in pane " + (root.blocker && root.blocker.pane ? root.blocker.pane : "") + "." }
    }
  }
}
