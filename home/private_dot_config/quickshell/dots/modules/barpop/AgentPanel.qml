pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"

// Body of the agent popup. `model` is js/Agents.js build(). Approve and Deny would answer
// an agent, which is a remote write: they render disabled. Jump to the pane is local.
Item {
  id: root

  property var model: ({ cards: [], quiet: true, pill: "All clear", lit: false, running: [], paused: [], done: [], budget: null })

  signal cardPicked(string id)
  signal jump(string ref)
  signal openCc()

  implicitWidth: 388
  implicitHeight: col.implicitHeight
  width: implicitWidth

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.l

    // header: logo glyph, title, pill, expand to the control centre
    Item {
      width: parent.width
      height: 32
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.l
        Gly { anchors.verticalCenter: parent.verticalCenter; name: "robot"; box: 18; color: Theme.color.accent }
        DText { anchors.verticalCenter: parent.verticalCenter; text: "Agents"; role: "headline" }
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.m
        Pill {
          id: agentPill
          objectName: "agentPill"
          anchors.verticalCenter: parent.verticalCenter
          text: root.model.pill
          tone: root.model.lit ? "accent" : "none"
          bordered: true
        }
        Item {
          width: 32; height: 32
          Gly { anchors.centerIn: parent; name: "arrows-out-simple"; box: 18; color: Theme.color.fgDim }
          MouseArea { anchors.fill: parent; onClicked: root.openCc() }
        }
      }
    }

    Column {
      visible: root.model.cards.length > 0
      width: parent.width
      spacing: Theme.space.m
      Lbl { text: "NEEDS YOU · OLDEST FIRST" }
      Repeater {
        model: root.model.cards
        Rectangle {
          id: card
          objectName: "agentCard"
          required property var modelData
          width: col.width
          height: modelData.focused ? full.implicitHeight + 2 * Theme.space.xl : 46
          radius: Theme.radius.row + 2
          color: modelData.focused ? Theme.color.surfaceContainer : Theme.color.surface
          border.width: 1
          border.color: modelData.focused ? Theme.color.accent : Theme.color.outlineVariant

          // compact line
          Row {
            visible: !card.modelData.focused
            anchors.fill: parent
            anchors.leftMargin: Theme.space.xl
            anchors.rightMargin: Theme.space.xl
            spacing: Theme.space.m
            StatusMark { anchors.verticalCenter: parent.verticalCenter; level: "waiting"; size: 12 }
            DText { anchors.verticalCenter: parent.verticalCenter; text: card.modelData.agent; role: "bodyS"; font.weight: Font.DemiBold }
            Cap {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 12 - 2 * Theme.space.m - 90 - 60
              text: card.modelData.verb
              dim: true; elide: Text.ElideRight
            }
            Cap { anchors.verticalCenter: parent.verticalCenter; text: card.modelData.age; dim: true }
          }
          MouseArea { anchors.fill: parent; visible: !card.modelData.focused; onClicked: root.cardPicked(card.modelData.id) }

          // full card
          Column {
            id: full
            visible: card.modelData.focused
            x: Theme.space.xl
            y: Theme.space.xl
            width: parent.width - 2 * Theme.space.xl
            spacing: Theme.space.m
            Row {
              spacing: Theme.space.m
              height: 24
              StatusMark { anchors.verticalCenter: parent.verticalCenter; level: "waiting"; size: 12 }
              DText { anchors.verticalCenter: parent.verticalCenter; text: card.modelData.agent; role: "bodyS"; font.weight: Font.DemiBold }
              Cap { anchors.verticalCenter: parent.verticalCenter; text: card.modelData.age; dim: true }
            }
            DText {
              width: parent.width
              wrapMode: Text.WordWrap
              text: card.modelData.verb
              role: "bodyS"; font.weight: Font.DemiBold
            }
            Cap {
              visible: card.modelData.obj !== ""
              width: parent.width
              text: card.modelData.obj
              dim: true; elide: Text.ElideRight
            }
            Row {
              spacing: Theme.space.m
              layoutDirection: Qt.RightToLeft
              width: parent.width
              Btn { objectName: "actApprove"; label: "Approve once"; kind: "primary"; stub: true }
              Btn { objectName: "actDeny"; label: "Deny"; stub: true }
              Btn { objectName: "actJump"; label: "Jump to pane"; stub: !card.modelData.canJump; tip: "no pane to jump to"; onClicked: root.jump(card.modelData.ref) }
            }
          }
        }
      }
    }

    DText {
      objectName: "quiet"
      visible: root.model.quiet
      text: "Nothing needs you"
      role: "bodyS"
      dim: true
    }

    // running agents
    Column {
      visible: root.model.running.length > 0
      width: parent.width
      spacing: Theme.space.m
      Lbl { text: "RUNNING · " + root.model.running.length }
      Repeater {
        model: root.model.running
        Item {
          id: run
          objectName: "runRow"
          required property var modelData
          width: col.width
          height: 44
          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Theme.space.s
            Row {
              width: parent.width
              DText { width: parent.width - runEl.implicitWidth; text: run.modelData.name + " · " + run.modelData.task; role: "bodyS"; elide: Text.ElideRight }
              Cap { id: runEl; text: run.modelData.el; dim: true }
            }
            Rectangle {
              width: parent.width; height: 3; radius: 1.5
              color: Qt.alpha(Theme.color.fg, 0.1)
              Rectangle {
                height: 3; radius: 1.5
                color: run.modelData.pct >= 0 ? Theme.color.accent : Theme.color.outline
                width: parent.width * (run.modelData.pct >= 0 ? run.modelData.pct / 100 : 0.3)
                x: run.modelData.pct >= 0 ? 0 : parent.width * 0.35
              }
            }
          }
        }
      }
    }

    Column {
      visible: root.model.paused.length > 0
      width: parent.width
      spacing: Theme.space.s
      Lbl { text: "PAUSED · " + root.model.paused.length }
      Repeater {
        model: root.model.paused
        Cap {
          required property var modelData
          width: col.width
          text: modelData.name + (modelData.why ? ", " + modelData.why : "")
          dim: true; elide: Text.ElideRight
        }
      }
    }

    Column {
      visible: root.model.done.length > 0
      width: parent.width
      spacing: Theme.space.s
      Lbl { text: "DONE" }
      Repeater {
        model: root.model.done
        Row {
          id: doneRow
          required property string modelData
          spacing: Theme.space.m
          Gly { anchors.verticalCenter: parent.verticalCenter; name: "check-circle"; box: 14; color: Theme.color.fgDim }
          Cap { text: doneRow.modelData; dim: true }
        }
      }
    }

    Item {
      visible: root.model.budget !== null
      width: parent.width
      height: visible ? 28 : 0
      Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }
      Cap { y: 8; text: "Budget today"; dim: true }
      Cap { objectName: "budget"; y: 8; anchors.right: parent.right; text: root.model.budget ? root.model.budget.text : ""; dim: false }
    }
  }
}
