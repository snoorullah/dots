pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../barpop"

// "Restore yesterday's layout?": what was saved, a checkbox per part, Restore or Start clean.
// Agents come back paused, so restoring never starts one. `m` comes from js/Restore.js build().
Item {
  id: root

  property var m: ({ show: false, title: "", saved: "", rows: [], parts: [], canRestore: false, warn: "" })
  property var result: null           // { launched, failed } once Restore ran
  signal toggled(string id)
  signal restore()
  signal clean()
  signal undo()

  implicitWidth: 480
  implicitHeight: col.implicitHeight
  width: implicitWidth
  height: implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.xl

    Lbl { text: "Restore after login" }
    DText { objectName: "promptTitle"; width: parent.width; text: root.m.title; role: "headline" }
    Cap { objectName: "savedAt"; text: root.m.saved }

    Column {
      width: parent.width
      spacing: Theme.space.s
      Repeater {
        model: root.m.rows
        Item {
          id: row
          required property var modelData
          required property int index
          objectName: "partRow"
          width: parent.width
          height: 34
          opacity: row.modelData.disabled ? 0.45 : 1
          Rectangle {
            objectName: "partBox"
            x: Theme.space.m
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 4
            color: row.modelData.on ? Theme.color.accent : "transparent"
            border.width: 1
            border.color: row.modelData.on ? Theme.color.accent : Theme.color.outline
            Gly { anchors.centerIn: parent; visible: row.modelData.on; name: "check"; box: 12; color: Theme.color.accentFg }
          }
          DText { objectName: "partLabel"; x: 40; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.label; role: "bodyS" }
          Cap { objectName: "partValue"; anchors.right: parent.right; anchors.rightMargin: Theme.space.m; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, parent.width - 40 - 200); horizontalAlignment: Text.AlignRight; text: row.modelData.value; elide: Text.ElideLeft }
          MouseArea { anchors.fill: parent; enabled: !row.modelData.disabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggled(row.modelData.id) }
        }
      }
    }

    Item {
      visible: !root.result
      width: parent.width
      height: visible ? 32 : 0
      Row {
        spacing: Theme.space.l
        Btn { objectName: "restoreBtn"; label: "Restore"; kind: "primary"; stub: !root.m.canRestore; tip: "pick at least one part"; onClicked: root.restore() }
        Btn { objectName: "cleanBtn"; label: "Start clean"; kind: "ghost"; onClicked: root.clean() }
      }
      Cap { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Enter \u00b7 Esc" }
    }

    Rectangle {
      objectName: "resultRow"
      visible: !!root.result
      width: parent.width
      height: visible ? 44 : 0
      radius: Theme.radius.row
      color: Theme.color.surfaceContainer
      Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.space.xl
        anchors.rightMargin: Theme.space.m
        Cap { objectName: "resultText"; anchors.verticalCenter: parent.verticalCenter; width: parent.width - undoBtn.width; text: root.result ? ("Reopened " + root.result.launched + (root.result.launched === 1 ? " item" : " items") + (root.result.failed > 0 ? ", " + root.result.failed + " failed" : "") + ". Undo stays for 10 s.") : ""; dim: false }
        Btn { id: undoBtn; anchors.verticalCenter: parent.verticalCenter; label: "Undo  z"; kind: "ghost"; onClicked: root.undo() }
      }
    }

    Cap { objectName: "warn"; width: parent.width; wrapMode: Text.WordWrap; text: root.m.warn; color: Theme.color.waiting; dim: false }
  }
}
