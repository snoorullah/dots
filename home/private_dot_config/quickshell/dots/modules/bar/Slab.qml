import QtQuick
import "../theme"

// One translucent slab holding a row of chips with hairline dividers between the
// VISIBLE ones. A slab with nothing visible has zero width.
Rectangle {
  id: slab

  default property alias chips: row.data
  property var tracked: []

  implicitHeight: Theme.bar.height
  // edge to text is 12: Theme.space.l (8) here plus Chip.pad (Theme.space.s, 4)
  implicitWidth: row.implicitWidth > 0 ? row.implicitWidth + 2 * Theme.space.l : 0
  visible: implicitWidth > 0
  color: Qt.alpha(Theme.color.surface, Theme.alpha.slab)
  radius: Theme.radius.chip

  function relayout() {
    var first = true;
    for (var i = 0; i < tracked.length; i++) {
      var c = tracked[i];
      c.divider = !first && c.shown;
      if (c.shown) first = false;
    }
  }

  Row {
    id: row
    x: Theme.space.l
    height: parent.height
    spacing: Theme.bar.chipGapPx
  }

  Component.onCompleted: {
    var list = [];
    for (var i = 0; i < row.children.length; i++) {
      var c = row.children[i];
      if (c.shown === undefined) continue;
      list.push(c);
      c.shownChanged.connect(slab.relayout);
    }
    tracked = list;
    relayout();
  }
}
