import QtQuick
import QtQuick.Shapes
import "../../theme"

// The crescent-and-light mark (Noor means light). Accent on a raised disc. Click opens the
// control centre. The path is the board's 32 x 32 drawing, drawn as a vector so it scales.
Item {
  id: logo

  property int disc: Theme.space.xxxl + Theme.space.s + 2   // 30
  property int mark: 20
  signal clicked()

  width: disc
  height: disc

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.pill
    color: Theme.color.surfaceContainer
  }
  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.pill
    color: Qt.alpha(Theme.color.fg, mouse.pressed ? Theme.alpha.pressed : Theme.alpha.hover)
    visible: mouse.containsMouse || mouse.pressed
  }

  Item {
    anchors.centerIn: parent
    width: logo.mark
    height: logo.mark

    Shape {
      width: 32
      height: 32
      scale: logo.mark / 32
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: Theme.color.accent
        strokeColor: "transparent"
        PathSvg { path: "M20.5 4.5a12 12 0 1 0 7 19.5 10 10 0 1 1-7-19.5Z" }
      }
      ShapePath {
        fillColor: Theme.color.accent
        strokeColor: "transparent"
        PathSvg { path: "M23 9l1.3 3.2 3.2 1.3-3.2 1.3L23 18l-1.3-3.2-3.2-1.3 3.2-1.3Z" }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: logo.clicked()
  }
}
