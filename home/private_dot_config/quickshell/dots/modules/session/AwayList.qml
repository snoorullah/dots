pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "js/Session.js" as S

// The step-out list: why are you leaving? `rows` comes from Session.awayRows. Enter takes
// the highlighted row (the first one at the start), 1-6 jump to a row and take it, arrows and
// Tab move, Esc cancels. This draws and emits; AwayPicker records and locks.
FocusScope {
  id: root

  property var rows: []
  property int current: 0
  signal picked(string key)
  signal cancelled()

  implicitHeight: col.implicitHeight

  Component.onCompleted: forceActiveFocus()

  function take(i) {
    if (i >= 0 && i < root.rows.length) root.picked(root.rows[i].key)
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape) { root.cancelled(); event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.take(root.current); event.accepted = true; return }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { root.current = S.step(root.current, root.rows.length, -1); event.accepted = true; return }
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { root.current = S.step(root.current, root.rows.length, 1); event.accepted = true; return }
    var j = S.jump(event.text, root.rows.length)
    if (j >= 0) { root.take(j); event.accepted = true }
  }

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.m

    Item {
      width: parent.width
      height: Theme.font.line.caption
      DText { role: "caption"; text: "Step out"; anchors.verticalCenter: parent.verticalCenter }
      DText { role: "bodyS"; dim: true; text: "Esc cancels"; anchors { right: parent.right; verticalCenter: parent.verticalCenter } }
    }

    Column {
      width: parent.width
      spacing: Theme.space.s
      Repeater {
        model: root.rows
        Rectangle {
          id: row
          required property var modelData
          required property int index
          readonly property bool sel: root.current === index
          objectName: "away-row-" + modelData.key
          width: parent.width
          height: 44
          radius: Theme.radius.row
          color: sel ? Qt.alpha(Theme.color.accent, Theme.alpha.on) : Qt.alpha(Theme.color.fg, area.containsMouse ? Theme.alpha.hover : Theme.alpha.rest)
          border.width: 1
          border.color: sel ? Theme.color.accent : Qt.alpha(Theme.color.outline, Theme.alpha.divider)

          SessGlyph {
            id: ico
            x: Theme.space.xl
            anchors.verticalCenter: parent.verticalCenter
            key: row.modelData.key
            boardSize: 16
            color: row.sel ? Theme.color.accent : Theme.color.fg
          }
          DText {
            anchors { left: ico.right; leftMargin: Theme.space.xl; right: chip.left; rightMargin: Theme.space.m; verticalCenter: parent.verticalCenter }
            text: row.modelData.label
            elide: Text.ElideRight
          }
          Rectangle {
            id: chip
            objectName: "away-hint-" + row.modelData.key
            anchors { right: parent.right; rightMargin: Theme.space.xl; verticalCenter: parent.verticalCenter }
            height: 20
            width: Math.max(20, hintText.implicitWidth + 2 * Theme.space.m)
            radius: Theme.radius.chip
            color: Qt.alpha(Theme.color.fg, row.sel ? Theme.alpha.on : Theme.alpha.rest * 2)
            DText { id: hintText; anchors.centerIn: parent; role: "bodyS"; mono: true; dim: true; text: row.sel ? "Enter" : row.modelData.hint }
          }
          MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.current = row.index
            onClicked: root.picked(row.modelData.key)
          }
        }
      }
    }

    DText {
      width: parent.width
      role: "bodyS"
      dim: true
      wrapMode: Text.WordWrap
      text: "Records why, then locks. Esc leaves without locking."
    }
  }
}
