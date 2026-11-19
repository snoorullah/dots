import QtQuick
import "../theme"

// A source that is stale or unavailable renders the shared unknown mark (the Phosphor
// "question" glyph, via StatusMark) in the unknown status colour. One unknown mark in
// the whole shell. Never a spinner: waiting is not news.
Item {
  id: root
  property bool on: false
  property int size: Theme.font.size.title

  implicitWidth: on ? size : 0
  implicitHeight: size
  visible: on

  StatusMark {
    anchors.fill: parent
    level: "unknown"
    size: root.size
  }
}
