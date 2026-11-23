pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../js/Queue.js" as Q

// Queue and Inbox: filter chips and Group by on top, sections below, detail on the right.
Item {
  id: pg
  property bool dim: false

  // keep the keyboard row inside the scroll viewport
  function reveal(row) {
    var y = row.mapToItem(fl.contentItem, 0, 0).y
    if (y < fl.contentY) fl.contentY = Math.max(0, y - 8)
    else if (y + row.height > fl.contentY + fl.height) fl.contentY = y + row.height - fl.height + 8
  }

  // hairline round the pane that holds the keyboard (list here, detail inside Detail)
  Item {
    x: 0
    y: 56
    width: parent.width - 500
    height: parent.height - 56
    z: 6
    FocusRing { kind: "pane"; focused: CcState.zone === "list" }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 0

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.color.outlineVariant }
        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          spacing: 8
          Repeater {
            model: CcState.srcList
            Chip {
              required property string modelData
              objectName: "filterChip"
              text: modelData
              icon: Q.srcIcon(modelData)
              on: CcState.src === modelData
              focused: on && CcState.chipFocus
              onClicked: CcState.src = modelData
            }
          }
          Item { Layout.fillWidth: true }
          Row {
            spacing: 4
            Icon { name: "rows"; size: 14; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
            DText { text: "Group by"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; anchors.verticalCenter: parent.verticalCenter }
          }
          Repeater {
            model: ["Urgency", "Source", "Person"]
            Seg {
              required property string modelData
              objectName: "groupSeg"
              text: modelData
              on: CcState.group === modelData
              focused: on && CcState.groupFocus
              onClicked: CcState.group = modelData
            }
          }
        }
      }

      Flickable {
        id: fl
        objectName: "queueScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: list.height + 24
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: list
          x: 12
          y: 8
          width: fl.width - 24
          Repeater {
            model: CcState.sections
            Column {
              id: sec
              required property var modelData
              width: list.width
              Item {
                objectName: "sectionHead"
                width: parent.width
                height: 16 + 16 + 6
                Row {
                  x: 8
                  y: 16
                  spacing: 6
                  Cap { text: sec.modelData.name }
                  Cap { text: sec.modelData.count; font.weight: Font.Normal }
                }
              }
              Repeater {
                model: sec.modelData.items
                QueueRow {
                  required property var modelData
                  item: modelData
                  dim: pg.dim
                  width: sec.width
                  current: CcState.effId === modelData.id
                  onPicked: { CcState.pane = "list"; CcState.pick(modelData.id) }
                  onRevealed: pg.reveal(this)
                }
              }
            }
          }
          DText {
            objectName: "emptyList"
            visible: CcState.sections.length === 0
            x: 8
            width: parent.width - 16
            topPadding: 40
            bottomPadding: 40
            text: "Nothing here. Back to your task."
            role: "title"
            font.weight: Font.Normal
            dim: true
          }
        }
      }
    }

    Detail {
      Layout.preferredWidth: 500
      Layout.fillHeight: true
    }
  }
}
