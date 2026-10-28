import QtQuick
import "../theme"
import "../common"
import "../../services"

// One module in a slab. Nominal means `shown: false`: zero width, not dim, and the Row
// that holds it forgets the gap too. A hidden module has no click target, which is why
// every conditional surface also has a keybind twin (docs/quickshell-shell.md).
Item {
  id: chip

  property bool shown: true
  property bool divider: false          // set by the Slab: a visible chip sits before this one
  property color tint: Theme.color.amber
  property bool wash: false             // the ONE use of colour: a wash behind the text
  property bool hoverable: true
  property int pad: Theme.space.s
  default property alias content: holder.data
  readonly property bool hovered: mouse.containsMouse

  property string screenName: ""

  signal clicked(var button)
  signal scrolled(int dy)

  // open a popout that points its notch at the middle of this chip
  function popout(name) {
    Ui.toggle(name, screenName, mapToItem(null, width / 2, 0).x);
  }

  implicitHeight: Theme.bar.height
  implicitWidth: shown ? holder.childrenRect.width + 2 * pad : 0
  width: implicitWidth
  height: implicitHeight
  visible: shown || implicitWidth > 0
  clip: true

  // enters over motion.base, leaves over motion.fast; never recolours, never pulses
  Behavior on implicitWidth {
    Anim {
      duration: chip.shown ? Theme.motion.base : Theme.motion.fast
      easing.type: chip.shown ? Theme.motion.easeIn : Theme.motion.easeOut
    }
  }

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: Theme.space.s
    anchors.bottomMargin: Theme.space.s
    radius: Theme.radius.chip
    color: Qt.alpha(chip.tint, Theme.alpha.wash)
    visible: chip.wash
  }

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: Theme.space.s
    anchors.bottomMargin: Theme.space.s
    radius: Theme.radius.chip
    color: Qt.alpha(Theme.color.fg, Theme.alpha.hover)
    visible: chip.hoverable && chip.hovered
  }

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: Theme.space.s
    anchors.bottomMargin: Theme.space.s
    radius: Theme.radius.chip
    color: Qt.alpha(Theme.color.fg, Theme.alpha.pressed)
    visible: chip.hoverable && mouse.pressed
  }

  Divider {
    visible: chip.divider
    y: (parent.height - height) / 2
  }

  Item {
    id: holder
    x: chip.pad
    width: childrenRect.width
    height: parent.height
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => chip.clicked(mouse.button)
    onWheel: wheel => chip.scrolled(wheel.angleDelta.y)
  }
}
