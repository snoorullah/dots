import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// The full views' top bar: filter field, result count, Salah pill, the view key.
Item {
  id: root
  property var m: ({})
  property bool readOnly: false
  property alias field: input
  signal edited(string q)
  signal keyed(var event)

  height: 60
  Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.alpha(Theme.color.outline, Theme.alpha.divider) }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Theme.space.xxl
    anchors.rightMargin: Theme.space.xxl
    spacing: Theme.space.xl

    Rectangle {
      objectName: "filterBox"
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - trail.width - Theme.space.xl
      height: 40
      radius: Theme.radius.row
      color: Theme.color.bg
      border.width: 1
      border.color: root.m.filtering || input.activeFocus ? Theme.color.accent : Theme.color.outlineVariant
      Gly { id: mag; x: Theme.space.xl; anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; box: 18; color: Theme.color.fgDim }
      TextInput {
        id: input
        x: mag.x + 18 + Theme.space.l + 2
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - count.width - 2 * Theme.space.xl
        readOnly: root.readOnly
        text: root.m.query || ""
        color: Theme.color.fg
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.body
        clip: true
        selectByMouse: true
        onTextEdited: root.edited(text)
        Keys.onPressed: event => root.keyed(event)
        DText {
          visible: input.text === ""
          anchors.verticalCenter: parent.verticalCenter
          text: "Type to filter windows, apps, workspaces"
          role: "bodyS"; dim: true
        }
      }
      Cap {
        id: count
        objectName: "resultCount"
        visible: !!root.m.filtering
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.xl
        anchors.verticalCenter: parent.verticalCenter
        text: root.m.resultsText || ""
        color: Theme.color.accent
      }
    }

    Row {
      id: trail
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.space.xl
      Pill { objectName: "maskPill"; visible: !!root.m.mask; anchors.verticalCenter: parent.verticalCenter; text: "Masked"; tone: "accent"; bordered: true }
      Pill { objectName: "salahPill"; visible: !!root.m.salah; anchors.verticalCenter: parent.verticalCenter; text: "Salah"; tone: "accent"; bordered: true }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "Tab view" }
    }
  }
}
