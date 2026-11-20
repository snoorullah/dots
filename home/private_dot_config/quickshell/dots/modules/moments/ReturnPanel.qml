import QtQuick
import "../common"

// Board section 3, "Leaving your task": where you are, the chip, and the note after returning.
MomentPanel {
  id: panel

  property string where: ""
  property var detour: null
  property var task: null
  property bool backDone: false
  property string next: ""

  title: "Leaving your task"
  icon: MomentIcons.back
  width: 560
  height: implicitHeight

  NoteBox {
    padY: 10
    DText { width: parent.width; role: "bodyS"; dim: true; text: panel.where }
  }
  ReturnChip {
    objectName: "panelChip"
    detour: panel.detour
    task: panel.task
    onReturned: panel.backDone = true
  }
  ReturnNote {
    objectName: "returnNote"
    visible: panel.backDone
    label: panel.detour ? panel.detour.label : ""
    next: panel.next
  }
}
