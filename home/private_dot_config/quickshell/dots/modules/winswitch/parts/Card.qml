pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// One window in the strip or grid: a schematic page (never a capture of the window), the
// profile and ticket chips, the app glyph, the title and the workspace.
Item {
  id: root
  property var c: ({})
  signal picked()

  readonly property bool sel: !!c.selected
  width: 200
  height: 158
  z: sel ? 3 : 1
  scale: sel ? 1.06 : 1
  opacity: c.dim ? 0.5 : (c.faded ? 0.4 : 1)
  Behavior on scale { Anim { duration: Theme.motion.fast } }

  function tone(t) {
    return t === "accent" ? Theme.color.accent
      : t === "dim" ? Theme.color.fgDim
      : t === "mid" ? Qt.alpha(Theme.color.accent, 0.45)
      : Theme.color.outline
  }

  // a collapsed group looks like a stack
  Rectangle { visible: !!root.c.group; x: 8; y: -6; width: parent.width - 16; height: 40; radius: Theme.radius.card; color: Theme.color.surfaceContainer; border.width: 1; border.color: Theme.color.outline }
  Rectangle { visible: !!root.c.group; x: 16; y: -12; width: parent.width - 32; height: 40; radius: Theme.radius.card; color: Theme.color.surface; border.width: 1; border.color: Theme.color.outline }

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Theme.radius.card
    color: Theme.color.surface
    clip: true
    border.width: root.sel ? 2 : 1
    border.color: root.sel || root.c.ring ? Theme.color.accent : Theme.color.outlineVariant

    Item {
      id: page
      x: 3; y: 0
      width: parent.width - 3
      height: 130
      Rectangle { anchors.fill: parent; color: Theme.color.bg }
      Column {
        visible: !root.c.unavail
        x: 14; y: 38
        spacing: 8
        Repeater {
          model: root.c.bars || []
          Rectangle {
            required property var modelData
            x: modelData[0]; width: modelData[1]; height: 4; radius: 2
            color: root.tone(modelData[2])
          }
        }
      }
      Gly { visible: !!root.c.unavail; anchors.horizontalCenter: parent.horizontalCenter; y: 36; name: "eye-closed"; box: 28; color: Theme.color.unknown }
      Tag { x: 8; y: 8; text: root.c.profile || ""; tone: "dim"; objectName: "profileTag" }
      Tag { visible: !!root.c.ticket; objectName: "ticketTag"; anchors.right: parent.right; anchors.rightMargin: 8; y: 8; text: root.c.ticket || ""; tone: "accent"; icon: "ticket" }
      Tag { visible: !!root.c.badge; objectName: "badgeTag"; anchors.right: parent.right; anchors.rightMargin: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; text: root.c.badge || ""; tone: "light"; icon: "tabs" }
      Cap { visible: !!root.c.dim; x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; text: root.c.dim || "" }
      Tag { visible: !!root.c.suggested; objectName: "suggestTag"; x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; text: "suggested"; tone: "solid" }
    }
    Rectangle { x: 0; y: 0; width: 3; height: parent.height; color: root.sel ? Theme.color.accent : Theme.color.outline }

    Rectangle {
      x: 3; y: 130
      width: parent.width - 3
      height: 28
      color: Theme.color.surfaceContainer
      Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }
      Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.space.m
        anchors.rightMargin: Theme.space.m
        spacing: 6
        Gly { anchors.verticalCenter: parent.verticalCenter; name: root.c.icon || "squares-four"; box: 14; color: root.sel ? Theme.color.accent : Theme.color.fg }
        Item {
          objectName: "winTitle"
          property string text: root.c.title || ""
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 14 - 6 - ws.width - 6
          height: 16
          clip: true
          Row {
            Cap { text: root.c.pre || ""; dim: false }
            Cap { visible: !!root.c.hit; text: root.c.hit || ""; dim: false; color: Theme.color.accent; font.weight: Font.DemiBold }
            Cap { text: root.c.post || ""; dim: false }
          }
        }
        Rectangle {
          id: ws
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(20, wsText.implicitWidth + 8); height: 18; radius: 6
          color: "transparent"; border.width: 1; border.color: Theme.color.outlineVariant
          Cap { id: wsText; anchors.centerIn: parent; text: root.c.ws || "" }
        }
      }
    }
  }
  MouseArea { anchors.fill: parent; onClicked: root.picked() }
}
