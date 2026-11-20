import QtQuick
import qs.modules.common

// A name, a duration and (when `w` >= 0) a share bar underneath.
Column {
  id: r
  property string n: ""
  property string v: ""
  property real w: -1
  spacing: 4
  Item {
    width: parent.width
    height: label.implicitHeight
    DText { id: label; width: parent.width - 70; text: r.n; role: "bodyS"; elide: Text.ElideRight }
    DText { anchors.right: parent.right; text: r.v; role: "bodyS"; dim: true }
  }
  Meter { visible: r.w >= 0; width: parent.width; value: r.w }
}
