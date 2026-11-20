import QtQuick
import "../common"

// What shows after a return: back on the task, same window.
NoteBox {
  id: note
  property string label: ""
  property string next: ""
  padY: 10

  DText {
    width: parent.width
    role: "bodyS"
    text: "Back on " + note.label + ", same window." + (note.next !== "" ? " next: " + note.next : "")
    elide: Text.ElideRight
  }
}
