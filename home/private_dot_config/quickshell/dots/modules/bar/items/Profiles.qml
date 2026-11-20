pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import ".."

// Profile icons: where my work is grouped. The active one is filled and bright, the rest
// outline and dim. STUB: no profile source yet, so `active` comes only from a matching
// workspace name and nothing here is clickable.
Row {
  id: root

  property var profiles: []        // [{ name, icon }]
  property string active: ""
  readonly property int dot: Theme.space.xxxl

  height: parent ? parent.height : dot
  spacing: Theme.space.m

  Repeater {
    model: root.profiles

    Item {
      id: p
      required property var modelData
      readonly property bool on: p.modelData.name === root.active

      objectName: "profile"
      width: root.dot
      height: root.dot
      anchors.verticalCenter: parent.verticalCenter

      Glyph {
        anchors.centerIn: parent
        name: p.modelData.icon
        active: p.on
        box: 17
        color: p.on ? Theme.color.fg : Theme.color.fgDim
      }
    }
  }
}
