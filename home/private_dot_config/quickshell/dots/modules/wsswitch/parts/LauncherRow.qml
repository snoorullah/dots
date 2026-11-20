import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// "Open <query> in launcher": what Enter does when no window matches, and a way out when one does.
// The launcher itself is the launcher team's; this row only hands it the text.
Rectangle {
  id: root
  property var launcher: null          // { query, text, sub } from js/Model.js, or null
  signal opened(string query)

  objectName: "launcherRow"
  visible: !!launcher
  height: visible ? 40 : 0
  radius: Theme.radius.row
  color: ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : "transparent"
  border.width: 1
  border.color: Theme.color.outlineVariant
  Row {
    anchors.fill: parent
    anchors.leftMargin: Theme.space.xl
    anchors.rightMargin: Theme.space.xl
    spacing: Theme.space.xl - 2
    Gly { anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; box: 16; color: Theme.color.accent }
    DText { objectName: "launcherText"; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16 - sub.implicitWidth - 2 * (Theme.space.xl - 2); text: root.launcher ? root.launcher.text : ""; role: "bodyS"; elide: Text.ElideRight; textFormat: Text.PlainText }
    Cap { id: sub; anchors.verticalCenter: parent.verticalCenter; text: root.launcher ? root.launcher.sub : "" }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.opened(root.launcher ? root.launcher.query : "") }
}
