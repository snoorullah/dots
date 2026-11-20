import QtQuick
import "../common"

// An icon sized by the box it should fill, not by font size. `dots Icons` draws its art at
// about 0.6 em, so a 16 px board icon needs a 27 px font; Icon.size is the font size.
Icon {
  property int box: 16

  size: Math.round(box / 0.6)
  implicitWidth: box
  implicitHeight: box
}
