pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"

// Body of the waiting popup. `model` is js/Waiting.js build(). Rows are the triage list;
// the focused row shows its actions. Draft, Snooze and Done would write somewhere, so
// they render disabled. Open (https only) and Jump are local.
Item {
  id: root

  property var model: ({ chips: [], rows: [], banner: null, empty: true, counts: ({}), title: "", icon: "clock", order: "", prayer: "", moreLabel: "", moreN: 0, count: 0 })

  // names Waiting.js hands to Icon; listed here so tools/gen-phosphor-qml.py keeps them in the registry
  readonly property var usedIcons: ({ all: "clock", mail: "envelope-simple", chat: "chat-text", agent: "robot", problem: "warning", other: "clipboard-text", prayer: "mosque" })

  signal chipPicked(string key)
  signal rowPicked(string id)
  signal jump(string ref)
  signal openUrl(string url)
  signal sidebar()

  implicitWidth: 328
  implicitHeight: col.implicitHeight
  width: implicitWidth

  function toneColor(t) {
    return t === "red" ? Theme.color.failed : (t === "amber" ? Theme.color.waiting : Theme.color.fgDim)
  }

  Column {
    id: col
    width: parent.width
    spacing: 0

    // header: title, count, kind chips, order line
    Column {
      width: parent.width
      spacing: Theme.space.m
      bottomPadding: Theme.space.l

      Row {
        width: parent.width
        height: 28
        spacing: Theme.space.l
        Gly { anchors.verticalCenter: parent.verticalCenter; name: root.model.icon; box: 18; color: Theme.color.accent }
        DText {
          objectName: "title"
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 18 - countText.implicitWidth - 2 * Theme.space.l
          text: root.model.title
          role: "title"
          elide: Text.ElideRight
        }
        DText { id: countText; objectName: "count"; anchors.verticalCenter: parent.verticalCenter; text: String(root.model.count); role: "headline"; mono: true }
      }
      Row {
        spacing: 4
        Repeater {
          model: root.model.chips
          Rectangle {
            id: chip
            objectName: "chip"
            required property var modelData
            height: 24
            width: chipText.implicitWidth + 2 * Theme.space.m + 2
            radius: height / 2
            color: chip.modelData.on ? Theme.color.accent : "transparent"
            border.width: 1
            border.color: chip.modelData.on ? Theme.color.accent : Theme.color.outlineVariant
            Cap {
              id: chipText
              anchors.centerIn: parent
              text: chip.modelData.label + (chip.modelData.n > 0 || chip.modelData.key === "all" ? " " + chip.modelData.n : "")
              color: chip.modelData.on ? Theme.color.accentFg : (chip.modelData.n > 0 ? Theme.color.fg : Theme.color.fgDim)
              dim: false
            }
            MouseArea { anchors.fill: parent; onClicked: root.chipPicked(chip.modelData.key) }
          }
        }
      }
      Item {
        width: parent.width
        height: 16
        Cap { objectName: "order"; text: root.model.order; dim: true; anchors.verticalCenter: parent.verticalCenter }
        Row {
          visible: root.model.prayer !== ""
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.space.s
          Gly { name: "mosque"; box: 13; color: Theme.color.waiting }
          Cap { objectName: "prayerHint"; text: root.model.prayer; color: Theme.color.waiting; dim: false }
        }
      }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }

    Rectangle {
      objectName: "banner"
      visible: root.model.banner !== null && root.model.banner !== undefined
      width: parent.width
      height: visible ? 32 : 0
      color: !root.model.banner ? "transparent" : Qt.alpha(root.model.banner.kind === "red" ? Theme.color.failed : Theme.color.unknown, 0.12)
      Row {
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.space.l
        spacing: Theme.space.l
        StatusMark {
          anchors.verticalCenter: parent.verticalCenter
          level: root.model.banner && root.model.banner.kind === "red" ? "failed" : "unknown"
          size: 14
        }
        Cap {
          anchors.verticalCenter: parent.verticalCenter
          text: root.model.banner ? root.model.banner.text : ""
          color: root.model.banner && root.model.banner.kind === "red" ? Theme.color.failed : Theme.color.fgDim
          dim: false
        }
      }
    }

    Column {
      id: rows
      width: parent.width
      topPadding: Theme.space.s
      bottomPadding: Theme.space.s
      spacing: 2

      Repeater {
        model: root.model.rows
        Rectangle {
          id: row
          objectName: "waitRow"
          required property var modelData
          width: rows.width
          height: topLine.height + (modelData.focused ? actions.height + Theme.space.l : 0)
          radius: Theme.radius.row
          color: modelData.focused ? Theme.color.surfaceContainer : "transparent"
          border.width: 0

          Item {
            id: topLine
            width: parent.width
            height: 46
            Row {
              anchors.fill: parent
              anchors.leftMargin: Theme.space.m
              anchors.rightMargin: Theme.space.m
              spacing: Theme.space.xl
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28; radius: Theme.radius.chip + 2
                color: row.modelData.focused ? Theme.color.surface : Theme.color.surfaceContainer
                Gly {
                  anchors.centerIn: parent
                  name: row.modelData.icon
                  box: 16
                  color: row.modelData.category === "problem" ? Theme.color.failed : Theme.color.fgDim
                }
              }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 28 - agePill.width - 2 * Theme.space.xl
                DText { objectName: "subj"; width: parent.width; text: row.modelData.subj; role: "body"; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Cap { width: parent.width; text: row.modelData.muted; dim: true; elide: Text.ElideRight }
              }
              Pill {
                id: agePill
                objectName: "ageChip"
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.age
                tone: row.modelData.tone
              }
            }
            MouseArea { anchors.fill: parent; onClicked: root.rowPicked(row.modelData.id) }
          }

          Row {
            id: actions
            visible: row.modelData.focused
            x: 46
            y: topLine.height
            spacing: Theme.space.s
            Btn { objectName: "actOpen"; label: "Open"; kind: "primary"; pad: Theme.space.l; stub: !row.modelData.canOpen; tip: "no link on this item"; onClicked: root.openUrl(row.modelData.url) }
            Btn { objectName: "actJump"; label: "Jump"; pad: Theme.space.l; stub: !row.modelData.canJump; tip: "no pane to jump to"; onClicked: root.jump(row.modelData.ref) }
            Btn { objectName: "actSnooze"; label: "Snooze"; pad: Theme.space.l; stub: true }
            Btn { objectName: "actDone"; label: "Done"; pad: Theme.space.l; stub: true }
          }
        }
      }

      Column {
        objectName: "emptyState"
        visible: root.model.empty
        width: parent.width
        topPadding: Theme.space.xxxl
        bottomPadding: Theme.space.xxxl
        leftPadding: Theme.space.xl
        spacing: Theme.space.s
        DText { text: "Nothing waiting"; role: "headline" }
        DText { text: "No one is waiting on you right now"; role: "bodyS"; dim: true }
      }
    }

    Rectangle { visible: !root.model.empty; width: parent.width; height: 1; color: Theme.color.outlineVariant }

    Item {
      objectName: "footer"
      visible: !root.model.empty
      width: parent.width
      height: visible ? 32 : 0
      Btn {
        objectName: "sidebarBtn"
        anchors.verticalCenter: parent.verticalCenter
        x: -Theme.space.l
        kind: "link"
        label: root.model.moreLabel
        onClicked: root.sidebar()
        // quiet buttons draw a border; the footer link reads better bare
      }
      Cap {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Esc closes"
        dim: true
      }
    }
  }
}
