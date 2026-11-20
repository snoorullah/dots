pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../js/Queue.js" as Q

// The right-hand detail of the selected item: what it is, the per-kind actions, and the
// compose or snooze panel under them. Compose panels type locally; every send is a stub.
Rectangle {
  id: d
  objectName: "detail"
  color: Qt.alpha(Theme.color.surface, 0.5)

  Rectangle { width: 1; height: parent.height; color: Theme.color.outlineVariant }

  readonly property var it: CcState.sel
  readonly property var composeLabel: !it ? "" : (it.kind === "msg" ? "Reply to " + it.who
    : it.kind === "ticket" ? "Comment on the ticket" : "Draft reply (saved to Drafts)")
  readonly property string sendLabel: !it ? "Send" : (it.kind === "ticket" ? "Post comment" : (it.kind === "mail" ? "Save draft" : "Send"))

  Flickable {
    anchors.fill: parent
    anchors.leftMargin: 1
    contentWidth: width
    contentHeight: col.height + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: col
      x: 24
      y: 20
      width: parent.width - 48
      spacing: 16

      DText {
        visible: !d.it
        Layout.fillWidth: true
        text: "Pick an item to see it here."
        dim: true
      }

      ColumnLayout {
        visible: !!d.it
        Layout.fillWidth: true
        spacing: 4
        Row {
          spacing: 6
          Icon { name: d.it ? Q.srcIcon(d.it.src) : "funnel"; size: 16; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
          DText { text: d.it ? d.it.src + " · " + d.it.who + " · waiting " + d.it.age : ""; role: "bodyS"; dim: true; anchors.verticalCenter: parent.verticalCenter }
        }
        DText { objectName: "detailTitle"; Layout.fillWidth: true; text: d.it ? d.it.title : ""; role: "headline"; wrapMode: Text.Wrap }
      }
      DText {
        visible: !!d.it
        Layout.fillWidth: true
        text: d.it ? d.it.body : ""
        role: "title"
        font.weight: Font.Normal
        wrapMode: Text.Wrap
      }
      DText { visible: !!d.it && d.it.ctx !== ""; Layout.fillWidth: true; text: d.it ? "Related: " + d.it.ctx : ""; role: "bodyS"; dim: true; wrapMode: Text.Wrap }
      Flow {
        visible: !!d.it
        Layout.fillWidth: true
        spacing: 14
        Repeater {
          model: d.it ? ["Kind: " + d.it.kind, "Source: " + d.it.src, "From: " + d.it.who, "Age: " + d.it.age, "Urgency: " + d.it.sec] : []
          DText { required property string modelData; text: modelData; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
        }
      }

      Flow {
        visible: !!d.it
        Layout.fillWidth: true
        spacing: 8
        Repeater {
          model: CcState.actions
          Btn {
            required property var modelData
            objectName: "action"
            text: modelData.label
            icon: modelData.icon
            keyHint: modelData.key
            primary: modelData.primary
            stub: modelData.effect === "stub"
            blocked: modelData.effect !== "stub" && !Q.canRun(modelData, CcState.sel)
            onClicked: CcState.run(modelData)
          }
        }
      }

      // reply / comment / draft: typing is local, Send is a stub
      ColumnLayout {
        objectName: "composeReply"
        visible: !!d.it && CcState.mode === "reply"
        Layout.fillWidth: true
        spacing: 8
        DText { text: d.composeLabel; role: "bodyS"; dim: true }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 96
          radius: Theme.radius.row
          color: Theme.color.bg
          border.width: 1
          border.color: Theme.color.outline
          TextEdit {
            anchors.fill: parent
            anchors.margins: 10
            color: Theme.color.fg
            font.family: Theme.font.mono
            font.pixelSize: Theme.font.size.bodyS
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            Keys.onEscapePressed: CcState.mode = ""
            DText { visible: parent.text === ""; text: "Type here. Only you can press Send."; role: "bodyS"; dim: true; opacity: 0.7 }
          }
        }
        Row {
          spacing: 8
          Btn { objectName: "sendBtn"; text: d.sendLabel; icon: "paper-plane-tilt"; primary: true; stub: true }
          Btn { text: "Cancel"; onClicked: CcState.mode = "" }
        }
      }

      // hand to an agent: the grant toggle is local state; handing over is a stub
      ColumnLayout {
        objectName: "composeAgent"
        visible: !!d.it && CcState.mode === "agent"
        Layout.fillWidth: true
        spacing: 8
        DText { text: "Tell the agent what to do"; role: "bodyS"; dim: true }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 72
          radius: Theme.radius.row
          color: Theme.color.bg
          border.width: 1
          border.color: Theme.color.outline
          TextEdit {
            anchors.fill: parent
            anchors.margins: 10
            color: Theme.color.fg
            font.family: Theme.font.mono
            font.pixelSize: Theme.font.size.bodyS
            wrapMode: TextEdit.Wrap
            text: "Get this done, then answer all their questions."
            selectByMouse: true
            Keys.onEscapePressed: CcState.mode = ""
          }
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: grantRow.implicitHeight + 24
          radius: Theme.radius.row
          color: Theme.color.surfaceContainer
          RowLayout {
            id: grantRow
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            Rectangle {
              Layout.alignment: Qt.AlignTop
              Layout.topMargin: 2
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              radius: 4
              color: CcState.grant ? Theme.color.accent : "transparent"
              border.width: 1
              border.color: CcState.grant ? Theme.color.accent : Theme.color.outline
              Icon { anchors.centerIn: parent; visible: CcState.grant; name: "check"; size: 12; color: Theme.color.accentFg }
              MouseArea { anchors.fill: parent; onClicked: CcState.grant = !CcState.grant }
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              DText { text: "May reply once to " + (d.it ? d.it.who : ""); role: "bodyS"; font.weight: Font.Medium }
              DText { Layout.fillWidth: true; text: "This thread only, then the permission ends. Logged under Agents. Anything else it tries is refused outside the AI."; role: "bodyS"; dim: true; wrapMode: Text.Wrap }
            }
          }
        }
        Row {
          spacing: 8
          Btn { objectName: "handBtn"; text: "Hand to agent"; icon: "paper-plane-tilt"; primary: true; stub: true }
          Btn { text: "Cancel"; onClicked: CcState.mode = "" }
        }
      }

      Flow {
        objectName: "composeSnooze"
        visible: !!d.it && CcState.mode === "snooze"
        Layout.fillWidth: true
        spacing: 8
        Repeater {
          model: ["30 minutes", "After this task", "Tonight", "Tomorrow"]
          Btn { required property string modelData; text: modelData; onClicked: CcState.snooze(modelData) }
        }
      }
    }
  }
}
