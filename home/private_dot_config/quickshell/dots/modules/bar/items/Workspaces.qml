pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"

// Workspaces as logos. The active one keeps its name and a raised wash; the others show
// only logos, and their name when hovered (or when they hold no app to show instead).
Row {
  id: root

  property var workspaces: []      // [{ id, name, active, apps: [{ cls, icon }], more }]
  property int pinHover: -1         // test hook: show this workspace's name as if hovered
  property int logo: Theme.font.size.title + 2    // 18
  signal focusRequested(int id)

  height: parent ? parent.height : Theme.space.xxxl
  spacing: Theme.space.s

  Repeater {
    model: root.workspaces

    Rectangle {
      id: ws
      required property var modelData
      readonly property bool showName: ws.modelData.active || hit.containsMouse || ws.modelData.id === root.pinHover || ws.modelData.apps.length === 0

      objectName: "workspace"
      property bool nameShown: showName
      height: Theme.space.xxxl + Theme.space.s + Theme.space.s + 2   // 30
      width: wsRow.implicitWidth + 2 * Theme.space.m
      anchors.verticalCenter: parent.verticalCenter
      radius: Theme.radius.pill
      color: ws.modelData.active ? Theme.color.surfaceContainerHigh
           : (hit.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent")

      Row {
        id: wsRow
        x: Theme.space.m
        height: parent.height
        spacing: Theme.space.s

        DText {
          objectName: "wsName"
          anchors.verticalCenter: parent.verticalCenter
          visible: ws.showName
          role: "bodyS"
          text: ws.modelData.name
          color: ws.modelData.active ? Theme.color.fg : Theme.color.fgDim
        }
        Repeater {
          model: ws.modelData.apps

          Item {
            id: app
            required property var modelData
            objectName: "wsLogo"
            width: root.logo
            height: root.logo
            anchors.verticalCenter: parent.verticalCenter
            opacity: ws.modelData.active ? 1 : 0.7

            Image {
              id: img
              anchors.fill: parent
              source: app.modelData.icon
              sourceSize: Qt.size(root.logo * 2, root.logo * 2)
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              visible: status === Image.Ready
            }
            // no icon found: the first letter on a raised square, never an empty gap
            Rectangle {
              anchors.fill: parent
              visible: img.status !== Image.Ready
              radius: Theme.radius.chip
              color: Theme.color.surfaceContainer
              DText {
                anchors.centerIn: parent
                role: "bodyS"
                text: app.modelData.cls.charAt(0).toUpperCase()
              }
            }
          }
        }
        DText {
          anchors.verticalCenter: parent.verticalCenter
          visible: ws.modelData.more > 0
          role: "bodyS"
          dim: true
          text: "+" + ws.modelData.more
        }
      }

      MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.focusRequested(ws.modelData.id)
      }
    }
  }
}
