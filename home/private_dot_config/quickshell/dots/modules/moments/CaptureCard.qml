import QtQuick
import Quickshell
import "../theme"
import "../common"
import "js/Moments.js" as M

// The quick capture card (board section 1). Enter, or the button, writes a local task by
// exec of an argv array (js/Moments.captureArgv). Tab (agent) and Ctrl+R (remind) are
// read-only stubs: dimmed, tooltip, no action. Esc asks to close.
MomentPanel {
  id: card

  property string backTo: MomentState.hasTask ? MomentState.backTo : ""
  property var enrichment: []          // lines the agent would add; nothing writes them yet
  property alias text: input.text
  property bool captured: false
  readonly property bool inputFocused: input.activeFocus

  signal submitted(string text)
  signal cancelled()

  title: "Quick capture"
  icon: MomentIcons.capture
  width: 480

  function focusInput() { input.forceActiveFocus(); }
  function reset() { input.text = ""; card.captured = false; }

  // true when a task was written. An empty thought writes nothing and stays open.
  function submit() {
    var argv = M.captureArgv(input.text);
    if (!argv) return false;
    Quickshell.execDetached(argv);
    card.captured = true;
    card.submitted(input.text);
    return true;
  }

  Column {
    width: parent.width
    spacing: 6

    DText {
      role: "bodyS"
      dim: true
      text: "Thought"
    }

    Rectangle {
      objectName: "captureInput"
      width: parent.width
      height: 48
      radius: Theme.radius.row
      color: Theme.color.surfaceContainer
      border.width: 1
      border.color: input.activeFocus ? Theme.color.accent : Theme.color.outline

      TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.color.fg
        selectionColor: Theme.color.accent
        selectedTextColor: Theme.color.accentFg
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.title
        clip: true
        selectByMouse: true
        maximumLength: 500
        Keys.onReturnPressed: card.submit()
        Keys.onEnterPressed: card.submit()
        Keys.onEscapePressed: card.cancelled()
        Keys.onTabPressed: function (e) { e.accepted = true; }       // agent: read-only stub
        Keys.onPressed: function (e) {                              // remind: read-only stub
          if (e.key === Qt.Key_R && (e.modifiers & Qt.ControlModifier)) e.accepted = true;
        }
      }
      DText {
        anchors.fill: input
        anchors.leftMargin: 0
        verticalAlignment: Text.AlignVCenter
        visible: input.text === ""
        font.pixelSize: Theme.font.size.title
        color: Theme.color.fgFaint
        text: "What came to mind?"
      }
    }
  }

  Row {
    id: hints
    objectName: "captureHints"
    spacing: 0
    Repeater {
      model: [
        { t: "Enter queue", stub: false }, { t: " · ", sep: true },
        { t: "Tab agent", stub: true }, { t: " · ", sep: true },
        { t: "Ctrl+R remind", stub: true }, { t: " · ", sep: true },
        { t: "Esc cancel", stub: false }
      ]
      Item {
        id: hint
        required property var modelData
        width: label.implicitWidth
        height: label.implicitHeight
        DText {
          id: label
          font.pixelSize: Theme.font.size.caption
          color: (hint.modelData.stub || hint.modelData.sep) ? Theme.color.fgFaint : Theme.color.fgDim
          text: hint.modelData.t
        }
        HoverHandler { id: hh; enabled: hint.modelData.stub === true }
        Rectangle {
          objectName: "hintTip"
          visible: hint.modelData.stub === true && hh.hovered
          z: 10
          y: -height - 4
          width: tt.implicitWidth + 16
          height: tt.implicitHeight + 8
          radius: Theme.radius.chip
          color: Theme.color.surfaceContainerHigh
          border.width: 1
          border.color: Theme.color.outline
          DText { id: tt; anchors.centerIn: parent; role: "bodyS"; text: "read-only for now" }
        }
      }
    }
  }

  MButton {
    objectName: "pressEnter"
    kind: "primary"
    text: "Press Enter"
    icon: MomentIcons.enter
    padX: 12
    gap: Theme.space.m
    corner: Theme.radius.row
    implicitHeight: 30
    onClicked: card.submit()
  }

  NoteBox {
    objectName: "capturedNote"
    visible: card.captured
    gap: 6
    DText {
      width: parent.width
      font.weight: Font.DemiBold
      text: card.backTo !== "" ? "You're already back on " + card.backTo + "." : "Saved to your task list."
    }
    DText {
      visible: card.enrichment.length > 0
      width: parent.width
      role: "bodyS"
      dim: true
      text: "In the background the agent adds:"
    }
    DText {
      visible: card.enrichment.length > 0
      width: parent.width
      font.pixelSize: Theme.font.size.caption
      lineHeight: 18
      color: Theme.color.fg
      text: card.enrichment.join("\n")
    }
  }
}
