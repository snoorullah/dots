pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// Filter results grouped by profile: window row with the match highlighted, its workspace,
// its state. Nothing matched says so.
Flickable {
  id: root
  property var m: ({})
  signal picked(string addr)
  contentHeight: col.implicitHeight + 12
  contentWidth: width
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: col
    x: Theme.space.xl
    width: parent.width - 2 * Theme.space.xl
    spacing: Theme.space.xl
    topPadding: Theme.space.m

    Repeater {
      model: root.m.groups || []
      Column {
        id: g
        required property var modelData
        objectName: "resGroup"
        width: col.width
        Row {
          x: Theme.space.m
          height: 28
          spacing: Theme.space.l
          Gly { anchors.verticalCenter: parent.verticalCenter; name: g.modelData.icon; box: 14; color: Theme.color.fgDim }
          DText { anchors.verticalCenter: parent.verticalCenter; text: g.modelData.name; role: "bodyS" }
          Cap { anchors.verticalCenter: parent.verticalCenter; text: g.modelData.n }
        }
        Repeater {
          model: g.modelData.rows
          Rectangle {
            id: r
            required property var modelData
            objectName: "resRow"
            width: g.width
            height: 40
            radius: Theme.radius.row
            color: r.modelData.sel ? Qt.alpha(Theme.color.accent, Theme.alpha.hover) : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : "transparent")
            Row {
              anchors.fill: parent
              anchors.leftMargin: Theme.space.xl
              anchors.rightMargin: Theme.space.xl
              spacing: Theme.space.xl - 2
              Chip { anchors.verticalCenter: parent.verticalCenter; icon: r.modelData.icon; tone: Theme.color.fgDim }
              Text {
                objectName: "resTitle"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24 - 12 - wsl.implicitWidth - 3 * (Theme.space.xl - 2)
                textFormat: Text.StyledText
                text: root.esc(r.modelData.pre) + (r.modelData.mid ? "<font color=\"" + Theme.color.accent + "\"><b>" + root.esc(r.modelData.mid) + "</b></font>" : "") + root.esc(r.modelData.post)
                color: Theme.color.fg
                font.family: Theme.font.mono
                font.pixelSize: Theme.font.size.bodyS
                elide: Text.ElideRight
              }
              Cap { id: wsl; anchors.verticalCenter: parent.verticalCenter; text: r.modelData.wsLabel }
              Dot { anchors.verticalCenter: parent.verticalCenter; kind: r.modelData.state }
            }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.picked(r.modelData.addr) }
          }
        }
      }
    }

    Item {
      objectName: "noMatch"
      visible: !!root.m.noResults
      width: parent.width
      height: visible ? 110 : 0
      Column {
        anchors.centerIn: parent
        spacing: Theme.space.m
        DText { anchors.horizontalCenter: parent.horizontalCenter; text: "No window matches."; role: "body" }
        Cap { anchors.horizontalCenter: parent.horizontalCenter; text: "Esc clears the filter." }
      }
    }
  }

  function esc(s) { return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
}
