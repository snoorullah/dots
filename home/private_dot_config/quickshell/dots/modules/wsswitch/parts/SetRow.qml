import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// "Back to last set": the profile's windows as they were when dots-layout last saved. One press
// reopens them; the toast that follows holds Undo. A profile with nothing saved says so.
Rectangle {
  id: root
  property var ret: ({ has: false })
  signal pressed()

  objectName: "setRow"
  height: 44
  radius: Theme.radius.row
  color: ma.containsMouse && ret.has ? Qt.alpha(Theme.color.accent, Theme.alpha.rest) : "transparent"
  border.width: 1
  border.color: ret.has ? Qt.alpha(Theme.color.accent, 0.4) : Theme.color.outlineVariant
  Row {
    anchors.fill: parent
    anchors.leftMargin: Theme.space.xl
    anchors.rightMargin: Theme.space.xl
    spacing: Theme.space.xl - 2
    Gly { anchors.verticalCenter: parent.verticalCenter; name: "arrow-counter-clockwise"; box: 16; color: root.ret.has ? Theme.color.accent : Theme.color.fgDim }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 16 - kc.implicitWidth - 2 * (Theme.space.xl - 2)
      DText { objectName: "setTitle"; width: parent.width; text: root.ret.has ? "Back to last set" : "No saved set yet"; role: "bodyS"; elide: Text.ElideRight }
      Cap { objectName: "setSub"; width: parent.width; text: root.ret.has ? root.ret.sub + " · " + root.ret.sum : "It forms once you work here."; elide: Text.ElideRight }
    }
    Cap { id: kc; anchors.verticalCenter: parent.verticalCenter; visible: root.ret.has; text: "b" }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: root.ret.has; cursorShape: Qt.PointingHandCursor; onClicked: root.pressed() }
}
