pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// `?` shows every key valid on the current page and zone, grouped Go, Move, Find, Time, Actions.
// The rows come from Keys.helpRows (CcState.helpGroups), the same tables resolve() uses.
Rectangle {
  id: h
  objectName: "helpOverlay"
  visible: CcState.helpOpen
  color: Qt.alpha(Theme.color.bg, 0.92)
  z: 50

  MouseArea { anchors.fill: parent; onClicked: CcState.helpOpen = false }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(640, parent.width - 48)
    height: Math.min(parent.height - 48, head.height + fl.contentHeight + 56)
    radius: Theme.radius.card
    color: Theme.color.surfaceContainer
    border.width: 1
    border.color: Theme.color.outlineVariant
    clip: true

    Column {
      id: head
      x: 24
      y: 20
      width: parent.width - 48
      DText { text: "Keys on " + CcState.pageId; role: "headline" }
      DText { text: "? or Esc closes. j k scrolls."; role: "bodyS"; dim: true; bottomPadding: 8 }
    }
    Flickable {
      id: fl
      objectName: "helpScroll"
      x: 24
      y: head.y + head.height + 8
      width: parent.width - 48
      height: parent.height - y - 16
      contentWidth: width
      contentHeight: col.height
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Connections {
        target: CcState
        function onHelpScrolled(dy) { fl.contentY = Math.max(0, Math.min(Math.max(0, fl.contentHeight - fl.height), fl.contentY + dy)) }
      }
      Column {
        id: col
        width: fl.width
        spacing: 2
        Repeater {
          model: CcState.helpGroups
          Column {
            id: grp
            required property var modelData
            width: col.width
            Cap { topPadding: 12; bottomPadding: 4; text: grp.modelData.name.toUpperCase() }
            Repeater {
              model: grp.modelData.rows
              Row {
                id: kr
                required property var modelData
                objectName: "helpRow"
                spacing: 16
                height: 24
                DText { width: 190; text: kr.modelData.keys; role: "bodyS"; mono: true; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                DText { text: kr.modelData.label; role: "bodyS"; dim: true; anchors.verticalCenter: parent.verticalCenter }
              }
            }
          }
        }
      }
    }
  }
}
