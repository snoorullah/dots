import QtQuick
import qs.modules.theme
import qs.modules.common

// A change with its direction: a caret turned up or down (a dash when flat) and the text, in a
// tone. good is the accent token, bad is the waiting token, neutral is dim. Never green.
Row {
  id: d
  property string dir: "flat"        // up | down | flat
  property string tone: "neutral"    // good | bad | neutral
  property string text: ""
  readonly property color tint: tone === "good" ? Theme.color.accent : (tone === "bad" ? Theme.color.waiting : Theme.color.fgDim)
  spacing: 4
  objectName: "delta"
  Item {
    width: 14
    height: 14
    anchors.verticalCenter: parent.verticalCenter
    Icon { visible: d.dir !== "flat"; anchors.centerIn: parent; name: "caret-right"; size: 14; color: d.tint; rotation: d.dir === "up" ? -90 : 90 }
    Rectangle { visible: d.dir === "flat"; anchors.centerIn: parent; width: 8; height: 2; radius: 1; color: d.tint }
  }
  DText { text: d.text; role: "bodyS"; mono: true; color: d.tint; anchors.verticalCenter: parent.verticalCenter }
}
