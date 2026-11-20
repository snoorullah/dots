import QtQuick
import "../common"

// An icon sized by the box it should fill, not by font size. `dots Icons` draws its art at
// about 0.6 em, so a 16 px board icon needs a 27 px font. The one place that factor lives:
// every barpop and calendar panel sizes icons with `box`, never with Icon.size.
Icon {
  objectName: "gly"
  property int box: 16
  readonly property real artRatio: 0.6
  // what the glyph actually paints, for the test probes
  readonly property int paintedPx: Math.round(size * artRatio)

  size: Math.round(box / artRatio)
  implicitWidth: box
  implicitHeight: box
}
