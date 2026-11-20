pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../barpop"

// Layout presets for the focused workspace: six tiles with a thumbnail, the one that fits the
// window count, and Apply. Driven by `m` from js/Presets.js build(); it touches nothing itself.
Item {
  id: root

  property var m: ({ presets: [], n: 0, canApply: false, count: "", lead: "", tail: "", name: "", selected: "" })
  signal picked(string id)
  signal apply(string id)

  implicitWidth: 560
  implicitHeight: col.implicitHeight
  width: implicitWidth
  height: implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.xl

    Lbl { objectName: "heading"; text: "Tiling assistant" }

    Grid {
      id: grid
      columns: 3
      spacing: Theme.space.l
      Repeater {
        model: root.m.presets
        Rectangle {
          id: tile
          required property var modelData
          objectName: "preset"
          width: Math.floor((col.width - 2 * grid.spacing) / 3)
          height: 92
          radius: Theme.radius.row
          color: tile.modelData.on ? Qt.alpha(Theme.color.accent, Theme.alpha.hover) : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : "transparent")
          border.width: 1
          border.color: tile.modelData.on ? Theme.color.accent : Theme.color.outlineVariant

          Item {
            id: thumb
            objectName: "thumb"
            x: Theme.space.m
            y: Theme.space.m
            width: parent.width - 2 * Theme.space.m
            height: 52
            Repeater {
              model: tile.modelData.rects
              Rectangle {
                id: r
                required property var modelData
                objectName: "thumbRect"
                x: r.modelData[0] * thumb.width
                y: r.modelData[1] * thumb.height
                width: r.modelData[2] * thumb.width
                height: r.modelData[3] * thumb.height
                radius: 3
                color: tile.modelData.on ? Theme.color.accent : Theme.color.outline
              }
            }
          }
          Cap { objectName: "presetName"; x: Theme.space.m + 2; anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.space.m; text: tile.modelData.name; dim: false; color: tile.modelData.on ? Theme.color.fg : Theme.color.fgDim }
          Cap { objectName: "presetKey"; anchors.right: parent.right; anchors.rightMargin: Theme.space.m + 2; anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.space.m; text: tile.modelData.key }
          MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.picked(tile.modelData.id) }
        }
      }
    }

    Cap { width: parent.width; wrapMode: Text.WordWrap; text: "A number picks, Enter applies. Each profile remembers its layout." }

    Rectangle {
      objectName: "applyRow"
      width: parent.width
      height: 44
      radius: Theme.radius.row
      color: Theme.color.surfaceContainer
      Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.space.xl
        anchors.rightMargin: Theme.space.m
        spacing: Theme.space.l
        Row {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - applyBtn.width - Theme.space.l
          spacing: Theme.space.s
          clip: true
          Cap { objectName: "countText"; anchors.verticalCenter: parent.verticalCenter; text: root.m.count; dim: false }
          Cap { objectName: "fitName"; anchors.verticalCenter: parent.verticalCenter; visible: root.m.lead !== "" && root.m.canApply; text: root.m.lead; dim: false; font.weight: Font.DemiBold; color: Theme.color.fg }
          Cap { objectName: "fitTail"; anchors.verticalCenter: parent.verticalCenter; visible: root.m.canApply; text: root.m.tail; dim: false }
        }
        Btn {
          id: applyBtn
          objectName: "applyBtn"
          anchors.verticalCenter: parent.verticalCenter
          label: "Apply"
          kind: "primary"
          stub: !root.m.canApply
          tip: "needs two or more windows"
          onClicked: root.apply(root.m.selected)
        }
      }
    }
  }
}
