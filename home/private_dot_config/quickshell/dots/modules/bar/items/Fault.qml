import QtQuick
import "../../theme"
import "../../common"
import ".."

// A problem, as its own chip. Failed: red diamond and the words. Unknown: a hollow "?" in
// the unknown grey and "data stale", never a confident blank. Shape first, colour second.
Chip {
  id: root

  property string kind: "none"     // none | failed | unknown
  property string text: ""

  objectName: "fault"
  visible: kind !== "none"
  padX: Theme.space.s

  // StatusMark's size is a font size, so it draws small here; same shapes, sized by box
  Glyph {
    anchors.verticalCenter: parent.verticalCenter
    name: root.kind === "failed" ? "diamond" : "question"
    active: true
    box: 14
    color: root.kind === "failed" ? Theme.color.failed : Theme.color.unknown
  }
  DText {
    anchors.verticalCenter: parent.verticalCenter
    role: "bodyS"
    font.weight: Theme.font.weight.label
    text: root.text
    color: root.kind === "failed" ? Theme.color.failed : Theme.color.unknown
  }
}
