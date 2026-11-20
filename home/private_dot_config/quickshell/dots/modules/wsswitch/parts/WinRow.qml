import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// One window in the tree: app tile, title, state dot. The selected row opens its hint line and
// the move-to buttons; a failed move shows the red row with Retry.
Item {
  id: root
  property var w: ({})
  property var targets: []
  property var hints: []
  property bool dim: false
  property string match: ""
  signal picked(string addr)
  signal move(string name)
  signal retry(string addr)

  objectName: "winRow"
  implicitHeight: head.height + (w.sel ? extra.height + Theme.space.xl : 0) + (w.err ? errRow.height + Theme.space.m : 0)
  opacity: dim ? 0.5 : 1

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.row
    color: root.w.sel ? Qt.alpha(Theme.color.accent, Theme.alpha.hover)
         : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : (root.w.moved ? Qt.alpha(Theme.color.accent, 0.08) : "transparent"))
  }

  Item {
    id: head
    width: parent.width
    height: 40
    Row {
      anchors.fill: parent
      anchors.leftMargin: Theme.space.xl
      anchors.rightMargin: Theme.space.xl
      spacing: Theme.space.xl - 2
      Chip { anchors.verticalCenter: parent.verticalCenter; icon: root.w.icon || "squares-four"; tone: root.w.app === "browser" || root.w.app === "editor" ? Theme.color.accent : Theme.color.fgDim }
      DText {
        objectName: "winTitle"
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 24 - 12 - 2 * (Theme.space.xl - 2)
        text: root.w.title || ""
        role: "bodyS"
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Dot { anchors.verticalCenter: parent.verticalCenter; kind: root.w.state || "running" }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.picked(root.w.addr)
    }
  }

  Rectangle {
    id: errRow
    visible: !!root.w.err
    objectName: "errRow"
    x: Theme.space.xl + 2
    y: head.height
    width: parent.width - 2 * Theme.space.xl
    height: errLine.implicitHeight + 2 * Theme.space.m + 2
    radius: 8
    color: Qt.alpha(Theme.color.failed, 0.08)
    border.width: 1
    border.color: Qt.alpha(Theme.color.failed, 0.5)
    Row {
      anchors.fill: parent
      anchors.margins: Theme.space.m + 2
      spacing: Theme.space.l
      Gly { anchors.verticalCenter: parent.verticalCenter; name: "warning"; box: 16; color: Theme.color.failed }
      Cap {
        id: errLine
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 16 - 64 - 2 * Theme.space.l
        text: "hyprctl dispatch did not return ok. Window not moved."
        color: Theme.color.failed
        wrapMode: Text.WordWrap
      }
      Rectangle {
        objectName: "retryBtn"
        anchors.verticalCenter: parent.verticalCenter
        width: 64; height: 32; radius: 8
        color: "transparent"
        border.width: 1
        border.color: Theme.color.failed
        Cap { anchors.centerIn: parent; text: "Retry"; color: Theme.color.failed }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.retry(root.w.addr) }
      }
    }
  }

  Column {
    id: extra
    visible: !!root.w.sel
    x: Theme.space.xl + 2
    y: head.height + (root.w.err ? errRow.height + Theme.space.m : 0)
    width: parent.width - 2 * Theme.space.xl
    spacing: Theme.space.l
    Hints { width: parent.width; items: root.hints }
    MoveBar { targets: root.targets; onPick: name => root.move(name) }
  }
}
