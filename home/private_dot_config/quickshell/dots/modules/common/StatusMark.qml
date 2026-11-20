import QtQuick
import "../theme"

// A status colour never appears without a shape (colour alone fails a colour-blind
// reader and any screenshot). waiting = filled circle, failed = filled diamond,
// unknown = question mark (cannot reach the data, so it never looks fine).
// Never animated, never pulsing.
Item {
  id: root

  property string level: "unknown"   // waiting | failed | unknown
  property int size: Theme.font.size.title

  implicitWidth: size
  implicitHeight: size

  Icon {
    anchors.fill: parent
    size: root.size
    name: root.level === "waiting" ? "circle" : (root.level === "failed" ? "diamond" : "question")
    active: root.level !== "unknown"
    color: root.level === "waiting" ? Theme.color.waiting
         : (root.level === "failed" ? Theme.color.failed : Theme.color.unknown)
  }
}
