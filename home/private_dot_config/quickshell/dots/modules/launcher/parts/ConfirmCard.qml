import QtQuick
import "../../theme"
import "../../common"

// A provider asked to confirm (kube context switch, anything destructive). Enter confirms, Esc cancels.
Rectangle {
  id: root

  required property var spec          // { title, detail, danger, label }
  property bool open: spec !== null && spec !== undefined
  color: Qt.alpha(Theme.color.bg, 0.62)
  visible: open
  signal confirmed()
  signal cancelled()

  MouseArea { anchors.fill: parent; onClicked: root.cancelled() }

  Surface {
    id: card
    objectName: "confirmCard"
    anchors.centerIn: parent
    width: 420
    height: body.implicitHeight + 40
    fill: 0.96

    Column {
      id: body
      x: 20; y: 20
      width: parent.width - 40
      spacing: 10
      DText { objectName: "confirmTitle"; width: parent.width; text: root.spec ? root.spec.title : ""; role: "title"; wrapMode: Text.WordWrap }
      DText { width: parent.width; text: root.spec && root.spec.detail ? root.spec.detail : ""; role: "bodyS"; dim: true; wrapMode: Text.WordWrap }
      Row {
        spacing: 6
        topPadding: 6
        ActionButton { objectName: "confirmCancel"; label: "Cancel  Esc"; onClicked: root.cancelled() }
        Rectangle {
          objectName: "confirmGo"
          height: 28; width: go.implicitWidth + 20; radius: 8
          color: root.spec && root.spec.danger ? Theme.color.failed : Theme.color.accent
          Text {
            id: go
            anchors.centerIn: parent
            text: (root.spec && root.spec.label ? root.spec.label : "Confirm") + "  Enter"
            color: root.spec && root.spec.danger ? Theme.color.bg : Theme.color.accentFg
            font.family: Theme.font.mono
            font.pixelSize: Theme.font.size.caption
            font.weight: Theme.font.weight.label
            renderType: Text.NativeRendering
          }
          MouseArea { anchors.fill: parent; onClicked: root.confirmed() }
        }
      }
    }
  }
}
