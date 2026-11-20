pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import "../js/Queue.js" as Q

// One list row: age, status mark, title and who/sub, source. 56 px min, radius row.
Item {
  id: r
  objectName: "queueRow"
  required property var item
  property bool current: false
  property bool dim: false
  signal picked()

  implicitHeight: 56
  width: parent ? parent.width : 400

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.row
    color: r.current ? Theme.color.surfaceContainer : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent")
  }
  RowLayout {
    anchors.fill: parent
    anchors.margins: 8
    spacing: 10
    DText {
      Layout.preferredWidth: 52
      horizontalAlignment: Text.AlignRight
      text: r.item.age
      role: "bodyS"
      color: r.item.tone === "wait" ? Theme.color.waiting : (r.item.tone === "fail" ? Theme.color.failed : Theme.color.fgDim)
      opacity: r.dim ? 0.6 : 1
    }
    Item {
      Layout.preferredWidth: 16
      Layout.preferredHeight: 16
      StatusMark {
        objectName: "rowMark"
        anchors.centerIn: parent
        visible: r.item.tone !== ""
        level: r.item.tone === "fail" ? "failed" : "waiting"
        size: 14
      }
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0
      DText { Layout.fillWidth: true; text: r.item.title; role: "body"; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; opacity: r.dim ? 0.6 : 1 }
      DText { Layout.fillWidth: true; text: r.item.who + " · " + r.item.sub; role: "bodyS"; dim: true; elide: Text.ElideRight }
    }
    Row {
      Layout.preferredWidth: 76
      Layout.alignment: Qt.AlignVCenter
      layoutDirection: Qt.RightToLeft
      spacing: 6
      DText { text: r.item.src; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; anchors.verticalCenter: parent.verticalCenter }
      Icon { name: Q.srcIcon(r.item.src); size: 16; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
    }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: r.picked() }
}
