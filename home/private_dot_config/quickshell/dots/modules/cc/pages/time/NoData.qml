import QtQuick
import qs.modules.common
import qs.modules.cc.parts

// An empty tab or card: one line that says exactly which source is missing.
Card {
  id: n
  property string title: ""
  property string icon: "clock"
  property string text: ""
  objectName: "timeNoData"
  Column {
    width: parent.width
    spacing: 8
    Head { text: n.title; icon: n.icon }
    DText { text: n.text; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
  }
}
