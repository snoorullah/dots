pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// Variant C: wide rail on the left; on the right the focused profile's workspace tabs and a
// schematic main + stack map of the chosen workspace. The map is drawn, not live: it shows
// which windows share a workspace, not where Hyprland put them.
Item {
  id: root
  property var m: ({})
  signal pickedProfile(string name)
  signal pickedWs(int index)
  signal pickedWin(string addr)
  signal focusWs(int id)
  signal move(string name)

  readonly property var fp: m.fp || ({ ws: [], total: 0, needs: 0, name: "", empty: true, primary: 1 })

  Rail { id: rail; wide: true; width: 220; height: parent.height; profiles: root.m.order || []; onPicked: name => root.pickedProfile(name) }
  Rectangle { x: rail.width; width: 1; height: parent.height; color: Qt.alpha(Theme.color.outline, Theme.alpha.divider) }

  Column {
    x: rail.width + 16
    y: 12
    width: parent.width - rail.width - 32
    spacing: Theme.space.l

    Item {
      width: parent.width; height: 36
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xl - 2
        DText { objectName: "profName"; anchors.verticalCenter: parent.verticalCenter; text: root.fp.name; role: "headline" }
        Pill { objectName: "needsPill"; visible: root.fp.needs > 0; anchors.verticalCenter: parent.verticalCenter; text: root.fp.needs + " need you"; tone: "amber"; bordered: true }
      }
      Cap { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.fp.total + (root.fp.total === 1 ? " window" : " windows") }
    }

    Row {
      height: 34
      spacing: 6
      Repeater {
        model: root.fp.ws
        Rectangle {
          id: tb
          required property var modelData
          required property int index
          objectName: "wsTab"
          width: tl.implicitWidth + 24; height: 34
          radius: 8
          color: tb.index === root.m.wsIdx ? Qt.alpha(Theme.color.accent, Theme.alpha.on) : "transparent"
          border.width: 1
          border.color: tb.index === root.m.wsIdx ? Theme.color.accent : Theme.color.outlineVariant
          Cap { id: tl; anchors.centerIn: parent; text: tb.modelData.label; color: tb.index === root.m.wsIdx ? Theme.color.accent : Theme.color.fg }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pickedWs(tb.index) }
        }
      }
    }

    Rectangle {
      id: stage
      objectName: "mapStage"
      width: parent.width
      height: 232
      radius: 12
      color: Theme.color.bg
      border.width: 1
      border.color: Theme.color.outlineVariant
      clip: true

      Item {
        objectName: "emptyMap"
        visible: root.fp.empty
        anchors.fill: parent
        anchors.margins: 14
        Rectangle { anchors.fill: parent; radius: 10; color: "transparent"; border.width: 1; border.color: Theme.color.outlineVariant }
        Column {
          anchors.centerIn: parent
          spacing: Theme.space.xl
          DText { anchors.horizontalCenter: parent.horizontalCenter; text: "Nothing open"; role: "body" }
          Btn { anchors.horizontalCenter: parent.horizontalCenter; label: "Go to workspace " + root.fp.primary; kind: "primary"; onClicked: root.focusWs(root.fp.primary) }
        }
      }

      Repeater {
        model: root.m.map || []
        Rectangle {
          id: t
          required property var modelData
          objectName: "mapTile"
          x: 4 + t.modelData.fx * (stage.width - 8)
          y: 4 + t.modelData.fy * (stage.height - 8)
          width: t.modelData.fw * (stage.width - 8)
          height: t.modelData.fh * (stage.height - 8)
          radius: 10
          opacity: root.m.query && !t.modelData.hit ? 0.35 : 1
          color: t.modelData.sel ? Qt.alpha(Theme.color.accent, Theme.alpha.on) : Theme.color.surface
          border.width: 1
          border.color: t.modelData.sel || (root.m.query && t.modelData.hit) ? Theme.color.accent : Theme.color.outlineVariant
          Column {
            anchors.fill: parent
            anchors.margins: 6
            Row {
              width: parent.width
              spacing: Theme.space.m
              Chip { anchors.verticalCenter: parent.verticalCenter; icon: t.modelData.icon; tone: Theme.color.fgDim }
              Cap { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 24 - 12 - 2 * Theme.space.m; text: t.modelData.title; dim: false; elide: Text.ElideRight }
              Dot { anchors.verticalCenter: parent.verticalCenter; kind: t.modelData.state }
            }
            Item { width: 1; height: Math.max(0, t.height - 12 - 24 - 16) }
            Cap { text: t.modelData.state === "needs" ? "needs you" : (t.modelData.state === "active" ? "focused" : "running") }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pickedWin(t.modelData.addr) }
        }
      }
    }

    MoveBar {
      objectName: "mapMove"
      visible: !!root.m.sel
      label: "Move " + (root.m.sel ? root.m.sel.title : "") + " to"
      targets: root.m.targets || []
      onPick: name => root.move(name)
    }

    Cap { objectName: "noMatchLine"; visible: !!root.m.noResults; text: "No window matches. Esc clears the filter."; dim: false }
  }
}
