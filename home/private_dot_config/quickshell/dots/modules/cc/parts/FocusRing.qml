import QtQuick
import qs.modules.theme
import "../js/Keys.js" as K

// The one focus rule (docs/shell/specs/cc-keys.md section 6). Put it inside the element that can
// hold keyboard focus and bind `focused`. It draws only after a key press, never after a mouse
// press, in the accent token: 2 px ring 2 px off the element, or a 1 px hairline for a pane.
Rectangle {
  id: r
  property bool focused: false
  property string kind: "element"       // element | pane
  readonly property var spec: K.ring(kind, focused, CcState.keyboard)
  objectName: "focusRing"
  visible: spec.visible
  anchors.fill: parent
  anchors.margins: -(spec.offset + (kind === "pane" ? 0 : spec.width))
  radius: kind === "pane" ? 0 : Theme.radius.row + spec.offset
  color: "transparent"
  border.width: spec.width
  border.color: Theme.color[spec.color]
  z: 5
}
